classdef TestParentKeyOptimization < matlab.unittest.TestCase
    % Metadata-only checks: no database connection or schema changes.
    properties (TestParameter)
        unsupported = struct( ...
            'or','etag="rest" OR channel=1', ...
            'and','etag="rest" AND subject="417"', ...
            'function','etag=LOWER("REST")', ...
            'qualified','child.etag="rest"', ...
            'in','etag IN ("rest")', ...
            'inequality','etag<>"rest"', ...
            'childOnly','channel=1', ...
            'escaped','etag="r\est"', ...
            'comment','etag="rest" -- comment')
    end
    methods (TestClassSetup)
        function addRepository(testCase)
            folder = fileparts(mfilename('fullpath'));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(folder)));
        end
    end
    methods (Test)
        function selectsSimpleQuotedKeyEqualities(testCase)
            table = TestParentKeyOptimization.metadata();
            conditions = {'etag="rest"','`subject` = ''417''','channel=1'};
            actual = dj.internal.parentKeyFilter(table,conditions);
            testCase.verifyEqual(actual.table,'`db`.`parent`');
            testCase.verifyEqual(actual.restrictions,conditions(1:2));
            testCase.verifyEqual(actual.attributes,{'run','subject','etag'});
        end
        function selectsScalarStructKeysOnly(testCase)
            table = TestParentKeyOptimization.metadata();
            actual = dj.internal.parentKeyFilter(table, ...
                {struct('etag','rest','channel',1)});
            testCase.verifyEqual(actual.restrictions,{struct('etag','rest')});
        end
        function acceptsNumericEqualityOnLeadingPrimaryKey(testCase)
            table = TestParentKeyOptimization.metadata();
            actual = dj.internal.parentKeyFilter(table,{'run=42'});
            testCase.verifyEqual(actual.restrictions,{'run=42'});
        end
        function skipsStructWithoutPrimaryKeys(testCase)
            table = TestParentKeyOptimization.metadata();
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table, ...
                {struct('status','error')}));
        end
        function skipsStructWithoutFields(testCase)
            table = TestParentKeyOptimization.metadata();
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table,{struct()}));
        end
        function resumesAfterStructWithoutPrimaryKeys(testCase)
            table = TestParentKeyOptimization.metadata();
            actual = dj.internal.parentKeyFilter(table, ...
                {struct('status','error'),struct('etag','rest','subject','417')});
            testCase.verifyEqual(actual.restrictions, ...
                {struct('etag','rest'),struct('subject','417')});
        end
        function skipsUnsupportedSql(testCase,unsupported)
            table = TestParentKeyOptimization.metadata();
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table,{unsupported}));
        end
        function skipsNegatedConditions(testCase)
            table = TestParentKeyOptimization.metadata();
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table, ...
                {'NOT',struct('etag','rest')}));
        end
        function resumesAfterNegatedCondition(testCase)
            table = TestParentKeyOptimization.metadata();
            actual = dj.internal.parentKeyFilter(table, ...
                {'NOT',struct('subject','417'),'etag="rest"'});
            testCase.verifyEqual(actual.restrictions,{'etag="rest"'});
        end
        function skipsStructArrayDisjunction(testCase)
            table = TestParentKeyOptimization.metadata();
            keys = [struct('etag','a'),struct('etag','b')];
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table,{keys}));
        end
        function skipsRenamedForeignKey(testCase)
            table = TestParentKeyOptimization.metadata();
            table.schema.conn.foreignKeys(1).aliased = true;
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table,{'etag="rest"'}));
        end
        function skipsNullableForeignKey(testCase)
            table = TestParentKeyOptimization.metadata();
            table.tableHeader.attributes(1).isnullable = true;
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table,{'etag="rest"'}));
        end
        function requiresKnownLeadingParentIndex(testCase)
            table = TestParentKeyOptimization.metadata();
            table.schema.conn.foreignKeys = table.schema.conn.foreignKeys(1);
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table,{'etag="rest"'}));
        end
        function skipsNonPrimaryForeignKey(testCase)
            table = TestParentKeyOptimization.metadata();
            table.schema.conn.foreignKeys(1).primary = false;
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table,{'etag="rest"'}));
        end
        function prefersMoreMatchingKeys(testCase)
            table = TestParentKeyOptimization.metadata();
            extra = table.schema.conn.foreignKeys(1);
            extra.ref = '`db`.`other`';
            extra.attrs = {'etag'};
            extra.ref_attrs = {'etag'};
            table.schema.headers('other') = struct('primaryKey',{{'etag'}});
            table.schema.conn.foreignKeys(end+1) = extra;
            actual = dj.internal.parentKeyFilter(table,{'etag="rest"','subject="417"'});
            testCase.verifyEqual(actual.table,'`db`.`parent`');
        end
        function skipsEquallySuitableParents(testCase)
            table = TestParentKeyOptimization.metadata();
            extra = table.schema.conn.foreignKeys;
            extra(1).ref = '`db`.`other`';
            extra(2).from = '`db`.`other`';
            table.schema.headers('other') = table.schema.headers('parent');
            table.schema.conn.foreignKeys = [table.schema.conn.foreignKeys extra];
            testCase.verifyEmpty(dj.internal.parentKeyFilter(table, ...
                {'etag="rest"','subject="417"'}));
        end
        function usesOwnNamespaceCache(testCase)
            table = TestParentKeyOptimization.metadata();
            table.schema.conn.schemas('db') = struct('dbname','db', ...
                'headers',containers.Map('KeyType','char','ValueType','any'));
            actual = dj.internal.parentKeyFilter(table,{'etag="rest"'});
            testCase.verifyEqual(actual.table,'`db`.`parent`');
        end
    end
    methods (Static, Access=private)
        function table = metadata()
            fields = {'run','subject','etag','channel'};
            attributes = struct('name',fields,'isnullable',false);
            header = struct('primaryKey',{fields},'attributes',attributes);
            link = struct('from','`db`.`child`','ref','`db`.`parent`', ...
                'attrs',{{'run','subject','etag'}}, ...
                'ref_attrs',{{'run','subject','etag'}},'primary',true,'aliased',false);
            backing = link;
            backing.from = link.ref;
            backing.ref = '`db`.`parms`';
            backing.attrs = {'etag'};
            backing.ref_attrs = {'etag'};
            headers = containers.Map('KeyType','char','ValueType','any');
            headers('parent') = struct('primaryKey',{{'run','subject','etag'}});
            schemas = containers.Map('KeyType','char','ValueType','any');
            connection = struct('foreignKeys',[link backing],'schemas',schemas);
            schema = struct('dbname','db','headers',headers,'conn',connection);
            table = struct('fullTableName','`db`.`child`','tableHeader',header,'schema',schema);
        end
    end
end
