classdef TestExistingUserCompatibility < matlab.unittest.TestCase
    % Regression checks using disconnected objects and local files only.
    properties (TestParameter)
        mapping = struct( ...
            'plain',struct('table','`unit`.`dimension`','expected','External.Dimension'), ...
            'computed',struct('table','`unit`.`__image`','expected','External.Image'), ...
            'renamedFKChild',struct('table','`unit`.`duty`','expected','External.Duty'), ...
            'namespaced',struct('table','`unit`.`ns/__epoch`','expected','ns.Epoch'), ...
            'unknown',struct('table','`unknown`.`table`','expected','`unknown`.`table`'))
        namespace = struct('plain','','prefixed','ns/')
    end
    methods (TestClassSetup)
        function addPaths(testCase)
            folder = fileparts(mfilename('fullpath'));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(folder)));
        end
    end
    methods (Test)
        function resolvesTableNamesWithoutConnecting(testCase,mapping)
            connection = dj.Connection('unused.invalid','unused','unused');
            testCase.addTeardown(@() delete(connection));
            connection.addPackage('unit','External');
            actual = connection.tableToClass(mapping.table);
            testCase.verifyEqual(actual,mapping.expected);
        end
        function drawsStandaloneAndNamespacedTiers(testCase,namespace)
            connection = dj.Connection('unused.invalid','unused','unused');
            testCase.addTeardown(@() delete(connection));
            connection.addPackage('unit','External');
            figureHandle = figure('Visible','off');
            testCase.addTeardown(@() delete(figureHandle));
            tables = {'#lookup','manual','_imported','__computed', ...
                '__computed__part','~external_main'};
            nodes = cellfun(@(name) ['`unit`.`' namespace name '`'], ...
                tables,'UniformOutput',false);
            diagram = djtestsupport.Diagram(connection,nodes);
            diagram.draw();
            testCase.verifyEqual(diagram.graph.numnodes,5);
            testCase.verifyEqual(diagram.graph.Nodes.marker, ...
                {'hexagram';'square';'o';'pentagram';'.'});
        end
        function configComparisonHandlesUnlimitedChunkRoundTrip(testCase)
            previous = dj.config;
            testCase.addTeardown(@() TestExistingUserCompatibility.restoreConfig(previous));
            file = [tempname '.json'];
            testCase.addTeardown(@() delete(file));
            fid = fopen(file,'w');
            fprintf(fid,'{"font":12}');
            fclose(fid);
            dj.config('rowDeleteChunk',Inf);
            base = TestConfig.TestConfig_configRemoveEnvVars(dj.config(),'config');
            base = regexprep(jsonencode(base),'[a-z0-9][A-Z]', ...
                '${$0(1)}_${lower($0(2))}');
            TestConfig.TestConfig_configSingleFileTest(testCase,'load-custom', ...
                file,jsondecode(base));
            testCase.verifyEqual(dj.config('rowDeleteChunk'),Inf);
        end
    end
    methods (Static, Access=private)
        function restoreConfig(config)
            dj.config.restore;
            for name = string(fieldnames(config))'
                dj.config(char(name),config.(name));
            end
        end
    end
end
