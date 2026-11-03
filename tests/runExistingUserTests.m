function results = runExistingUserTests(pv)
%runExistingUserTests - Run tests using DJ_HOST, DJ_USER, and DJ_PASS
%   RESULTS = runExistingUserTests() runs MainExistingUser without creating,
%   granting permissions to, or dropping database users. The existing account
%   needs permissions to create and drop uniquely prefixed test databases.
%   Tests write and delete test data; this is not a read-only test suite.
%
%   The djssl-account test is skipped. S3 tests require S3_* credentials;
%   other TLS tests exercise the supplied account and server configuration.
%   RESULTS = runExistingUserTests(useTLS=false) disables TLS and excludes
%   the secure/preferred-TLS tests for servers without TLS support.
%
%   See also MainExistingUser, PrepExistingUser
arguments
    pv.useTLS (1,1) logical = true
end
testsRoot = fileparts(mfilename('fullpath'));
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath));
addpath(testsRoot,'-begin');
addpath(fileparts(testsRoot));
suite = matlab.unittest.TestSuite.fromClass(?MainExistingUser);
if ~pv.useTLS
    previousTLS = dj.config('databaseUse_tls');
    tlsCleanup = onCleanup(@() dj.config('databaseUse_tls',previousTLS));
    dj.config('databaseUse_tls',false);
    requiresTLS = contains(string({suite.Name}), ...
        ["/TestTls_testSecureConn", "/TestTls_testPreferredConn"]);
    suite = suite(~requiresTLS);
end
suite = [suite, matlab.unittest.TestSuite.fromClass(?TestExistingUserCompatibility), ...
    matlab.unittest.TestSuite.fromClass(?TestExistingUserHarness)];
results = run(suite);
if nargout == 0
    assertSuccess(results);
end
end
