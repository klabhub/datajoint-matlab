classdef PrepExistingUser < Prep
    %PrepExistingUser - Test setup using an existing database account
    %   Uses DJ_HOST, DJ_USER, and DJ_PASS. No database accounts or grants
    %   are created or removed. Tests may create and drop schemas under a
    %   unique djtest_<id> prefix; the account needs those permissions.
    %   Optional S3 tests use S3_* credentials and a unique temporary bucket.
    properties (Access=private)
        workspace = ''
        originalConfig
        originalInit = ''
        originalDims = ''
        globalConfigFile = ''
        globalConfigBackup = ''
        hadGlobalConfig = false
        connected = false
        bucketCreated = false
        hasS3 = false
    end

    methods (TestClassSetup)
        function init(testCase)
            info = testCase.CONN_INFO;
            assert(~isempty(info.host) && ~isempty(info.user), ...
                'DataJoint:Tests:Credentials','Set DJ_HOST and DJ_USER before running this suite.');
            testCase.originalConfig = dj.config;
            testCase.originalInit = getenv('DJ_INIT');
            testCase.originalDims = getenv('MYM_USE_32BIT_DIMS');
            id = strrep(char(java.util.UUID.randomUUID),'-','');
            testCase.PREFIX = ['djtest_' id(1:16)];
            testCase.workspace = tempname;
            mkdir(testCase.workspace);
            testCase.addTeardown(@() testCase.cleanupLocal());
            testCase.addTeardown(@() testCase.cleanupDatabase());
            sourceRoot = fileparts(mfilename('fullpath'));
            testCase.test_root = testCase.workspace;
            testCase.external_file_store_root = fullfile(testCase.workspace,'store');
            schemaRoot = fullfile(testCase.workspace,'test_schemas');
            copyfile(fullfile(sourceRoot,'test_schemas'),schemaRoot);
            packages = dir(fullfile(schemaRoot,'+*'));
            for k = 1:numel(packages)
                generated = fullfile(schemaRoot,packages(k).name,'getSchema.m');
                if isfile(generated)
                    delete(generated);
                end
                clear([packages(k).name(2:end) '.getSchema']);
            end
            % TestConfig writes both local and global configuration files.
            home = char(java.lang.System.getProperty('user.home'));
            if ispc
                home = getenv('USERPROFILE');
            end
            testCase.globalConfigFile = fullfile(home,'.datajoint_config.json');
            testCase.hadGlobalConfig = isfile(testCase.globalConfigFile);
            if testCase.hadGlobalConfig
                testCase.globalConfigBackup = fullfile(testCase.workspace,'global_config_backup.json');
                copyfile(testCase.globalConfigFile,testCase.globalConfigBackup);
            end
            testCase.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(testCase.workspace));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(schemaRoot));
            dj.config('databaseHost',info.host);
            dj.config('databaseUser',info.user);
            dj.config('databasePassword',info.password);
            dj.config('safemode',false);
            dj.conn(info.host,info.user,info.password,'',true);
            testCase.connected = true;
            s3 = testCase.S3_CONN_INFO;
            testCase.hasS3 = all(structfun(@(value) ~isempty(value),s3));
            if testCase.hasS3
                try
                    dj.store_plugins.S3.RESTCallAWSSigned('http://',s3.endpoint, ...
                        ['/' s3.bucket],uint8(''),s3.access_key,s3.secret_key,'put');
                    testCase.bucketCreated = true;
                catch
                    testCase.hasS3 = false;
                    warning('DataJoint:Tests:S3Unavailable', ...
                        'Cannot create the temporary S3 bucket; S3 tests will be skipped.');
                end
            end
            fprintf('Existing-user test schemas: %s_*\n',testCase.PREFIX);
        end
    end

    methods
        function requireAvailableServices(testCase,service)
            if nargin < 2
                service = '';
            end
            if strcmp(service,'djssl')
                testCase.assumeFail('Requires the separately provisioned djssl account.');
            elseif strcmp(service,'s3')
                testCase.assumeTrue(testCase.hasS3, ...
                    'S3 credentials and successful temporary-bucket setup are required for S3 tests.');
            end
        end
    end

    methods (TestClassTeardown)
        function dispose(~)
            % Override Prep's privileged teardown; registered cleanup owns
            % only this run's schemas, temporary files, and optional bucket.
        end
    end

    methods (Access=protected)
        function info = connectionInfo(~)
            info = struct('host',getenv('DJ_HOST'),'user',getenv('DJ_USER'), ...
                'password',getenv('DJ_PASS'));
        end
        function info = s3ConnectionInfo(testCase)
            info = s3ConnectionInfo@Prep(testCase);
            if ~isempty(info.bucket)
                base = lower(regexprep(info.bucket,'[^a-zA-Z0-9-]','-'));
                base = base(1:min(25,numel(base)));
                info.bucket = [base '-' strrep(testCase.PREFIX,'_','-')];
            end
        end
    end

    methods (Access=private)
        function cleanupDatabase(testCase)
            if testCase.connected
                info = testCase.CONN_INFO;
                connection = dj.conn(info.host,info.user,info.password,'',true);
                connection.cancelTransaction;
                databases = connection.query('SHOW DATABASES');
                fields = fieldnames(databases);
                names = databases.(fields{1});
                assert(~isempty(regexp(testCase.PREFIX,'^djtest_[a-f0-9]{16}$','once')));
                checks = connection.query('SELECT @@FOREIGN_KEY_CHECKS AS enabled');
                restoreChecks = onCleanup(@() connection.query( ...
                    sprintf('SET FOREIGN_KEY_CHECKS=%d',checks.enabled)));
                connection.query('SET FOREIGN_KEY_CHECKS=0');
                for k = 1:numel(names)
                    if startsWith(names{k},[testCase.PREFIX '_'])
                        connection.query(sprintf('DROP DATABASE `%s`',names{k}));
                    end
                end
            end
            if testCase.bucketCreated
                s3 = testCase.S3_CONN_INFO;
                dj.store_plugins.S3.RESTCallAWSSigned('http://',s3.endpoint, ...
                    ['/' s3.bucket],uint8(''),s3.access_key,s3.secret_key,'delete');
            end
        end

        function cleanupLocal(testCase)
            if testCase.hadGlobalConfig
                copyfile(testCase.globalConfigBackup,testCase.globalConfigFile);
            elseif ~isempty(testCase.globalConfigFile) && isfile(testCase.globalConfigFile)
                delete(testCase.globalConfigFile);
            end
            setenv('DJ_INIT',testCase.originalInit);
            dj.config.restore;
            for name = string(fieldnames(testCase.originalConfig))'
                dj.config(char(name),testCase.originalConfig.(name));
            end
            setenv('MYM_USE_32BIT_DIMS',testCase.originalDims);
            if ~isempty(testCase.workspace) && isfolder(testCase.workspace)
                packages = dir(fullfile(testCase.workspace,'test_schemas','+*'));
                for k = 1:numel(packages)
                    clear([packages(k).name(2:end) '.getSchema']);
                end
                target = char(java.io.File(testCase.workspace).getCanonicalPath());
                parent = char(java.io.File(tempdir).getCanonicalPath());
                assert(startsWith([target filesep],[parent filesep]), ...
                    'DataJoint:Tests:CleanupPath','Test workspace must be inside the temporary directory.');
                rmdir(target,'s');
            end
        end
    end
end
