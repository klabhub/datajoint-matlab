classdef TestExistingUserHarness < matlab.unittest.TestCase
    % Test discovery and credential selection without database operations.
    methods (TestClassSetup)
        function addTestPaths(testCase)
            folder = fileparts(mfilename('fullpath'));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(folder)));
        end
    end
    methods (Test)
        function ordinaryTestsDoNotRequireTestCaseName(testCase)
            instance = MainExistingUser;

            instance.requireAvailableServices();

            testCase.verifyFalse(isprop(instance,'Name'));
        end

        function serviceGuardsAreExplicitTestOverrides(testCase)
            metadata = ?MainExistingUser;
            names = {'TestTls_testRejectException', ...
                'TestExternalS3_testRemoteDefault','TestExternalS3_testBackward', ...
                'TestExternalS3_testBackwardDefault','TestExternalS3_testLocationFlexibility'};
            guarded = metadata.MethodList(ismember({metadata.MethodList.Name},names));

            testCase.verifyNumElements(guarded,5);
            testCase.verifyTrue(all(arrayfun(@(method) ...
                strcmp(method.DefiningClass.Name,'MainExistingUser'),guarded)));
        end

        function existingSuiteOverridesPrivilegedSetup(testCase)
            metadata = ?MainExistingUser;
            setup = metadata.MethodList(strcmp({metadata.MethodList.Name},'init'));
            teardown = metadata.MethodList(strcmp({metadata.MethodList.Name},'dispose'));

            testCase.assertNumElements(setup,1);
            testCase.assertNumElements(teardown,1);
            testCase.verifyEqual(setup.DefiningClass.Name,'MainExistingUser');
            testCase.verifyEqual(teardown.DefiningClass.Name,'MainExistingUser');
        end

        function existingSuiteUsesRegularEnvironmentVariables(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture('DJ_HOST','host.invalid'));
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture('DJ_USER','existing-user'));
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture('DJ_PASS','test-password'));
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture('DJ_TEST_HOST','unused.invalid'));
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture('DJ_TEST_USER','unused-user'));
            instance = MainExistingUser;

            info = instance.CONN_INFO;

            testCase.verifyTrue(isequal(info,struct('host','host.invalid', ...
                'user','existing-user','password','test-password')));
        end

        function existingSuiteReusesAllOriginalTestMethods(testCase)
            original = matlab.unittest.TestSuite.fromClass(?Main);
            existing = matlab.unittest.TestSuite.fromClass(?MainExistingUser);
            originalMethods = extractAfter(string({original.Name}),'/');
            existingMethods = extractAfter(string({existing.Name}),'/');

            testCase.verifyEqual(sort(existingMethods),sort(originalMethods));
        end
    end
end
