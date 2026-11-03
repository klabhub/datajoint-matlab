classdef MainExistingUser < Main & PrepExistingUser
    %MainExistingUser - Existing DataJoint tests without account provisioning
    %   Run with runExistingUserTests. Uses the original test methods with
    %   PrepExistingUser setup and cleanup. The special-account TLS test is
    %   skipped, as are S3 tests when S3 credentials are not configured.
    methods (TestClassSetup)
        function init(testCase)
            init@PrepExistingUser(testCase);
        end
    end
    methods (TestClassTeardown)
        function dispose(testCase)
            dispose@PrepExistingUser(testCase);
        end
    end
    methods (Test)
        function TestTls_testRejectException(testCase)
            testCase.requireAvailableServices('djssl');
        end
        function TestExternalS3_testRemoteDefault(testCase)
            testCase.requireAvailableServices('s3');
            TestExternalS3_testRemoteDefault@Main(testCase);
        end
        function TestExternalS3_testBackward(testCase)
            testCase.requireAvailableServices('s3');
            TestExternalS3_testBackward@Main(testCase);
        end
        function TestExternalS3_testBackwardDefault(testCase)
            testCase.requireAvailableServices('s3');
            TestExternalS3_testBackwardDefault@Main(testCase);
        end
        function TestExternalS3_testLocationFlexibility(testCase)
            testCase.requireAvailableServices('s3');
            TestExternalS3_testLocationFlexibility@Main(testCase);
        end
    end
    methods (Access=protected)
        function info = connectionInfo(testCase)
            info = connectionInfo@PrepExistingUser(testCase);
        end
        function info = s3ConnectionInfo(testCase)
            info = s3ConnectionInfo@PrepExistingUser(testCase);
        end
    end
end
