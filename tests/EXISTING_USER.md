# Tests with an existing database account

`MainExistingUser` reuses the original `Main` test methods with the
`PrepExistingUser` setup and cleanup. Database credentials come exclusively
from `DJ_HOST`, `DJ_USER`, and `DJ_PASS`; `DJ_TEST_*` variables are ignored.
It does not create, grant permissions to, or drop database users.

From the datajoint-matlab repository, run:

```matlab
addpath(pwd)
addpath(fullfile(pwd,'tests'))
results = runExistingUserTests;
assertSuccess(results)
```

For a server without TLS, use `results = runExistingUserTests(useTLS=false)`.
This disables TLS for the run and excludes the secure/preferred-TLS tests;
the insecure-connection test remains included. The previous TLS setting is
restored afterward.

The account must already have permission to create tables and to insert,
update, delete, create, and drop databases named `djtest_*`. Each run uses a
unique prefix and cleanup drops only databases starting with that prefix.
The tests modify and delete test data; this is not a read-only suite.

The `djssl`-specific TLS rejection test is skipped. Other TLS tests run against
the supplied account and require the corresponding server capabilities.
When `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and `S3_BUCKET` are all set,
S3 tests use a uniquely named temporary bucket derived from `S3_BUCKET`.
Otherwise S3 tests are skipped. The supplied bucket itself is not changed.

Schema files, local configuration files, and external-file storage are copied
or created in a temporary working directory. Global DataJoint configuration
is backed up and restored, along with the prior in-memory configuration and
environment settings changed by the configuration tests. Use a dedicated
MATLAB session: connection tests replace the active DataJoint connection.

To verify inheritance and discovery without running the database suite:

```matlab
results = runtests('TestExistingUserHarness');
assertSuccess(results)
results = runtests('TestExistingUserCompatibility');
assertSuccess(results)
```

The original `Main` and `Prep` remain the provisioned-account suite; do not
use `runtests('tests')` when you intend to avoid its account-provisioning setup.
