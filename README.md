[![View DataJoint on File Exchange](https://www.mathworks.com/matlabcentral/images/matlab-file-exchange.svg)](https://www.mathworks.com/matlabcentral/fileexchange/63218-datajoint)

# Welcome to DataJoint for MATLAB!

> ## 📌 Maintenance status: community stewardship
>
> DataJoint Inc. has shifted its core development focus to the **Python-centered ecosystem** — [`datajoint-python`](https://github.com/datajoint/datajoint-python), the DataJoint Platform, and related tools. `datajoint-matlab` is now in **community-stewardship mode**: we are no longer proactively developing or supporting it, but we welcome pull requests from the community and will review well-formed, tested contributions on a best-effort basis.
>
> If you are starting a new DataJoint project, we recommend the Python-based stack. See **[docs.datajoint.com](https://docs.datajoint.com)** for the current documentation, tools, and platform overview.
>
> Existing users: this package remains functional and free to use under its existing license. Issues and PRs may not receive timely responses, but well-formed community contributions are appreciated.


DataJoint for MATLAB is a high-level programming interface for relational databases designed to support data processing chains in science labs. DataJoint is built on the foundation of the relational data model and prescribes a consistent method for organizing, populating, and querying data.

For MATLAB-specific documentation, see the [DataJoint MATLAB documentation site](https://datajoint.github.io/datajoint-matlab/) (built from `docs/src/` in this repo).

## For Developers: Running Tests Locally

<details>
<summary>Click to expand details</summary>

+ Create an `.env` with desired development environment values e.g.

``` sh
MATLAB_USER=rguzman
MATLAB_LICENSE=IyBCRUd... # For image usage instructions see https://github.com/guzman-raphael/matlab, https://hub.docker.com/r/raphaelguzman/matlab
MATLAB_VERSION=R2019a
MATLAB_HOSTID=XX:XX:XX:XX:XX:XX
MATLAB_UID=1000
MATLAB_GID=1000
MYSQL_TAG=5.7
MINIO_VER=RELEASE.2022-01-03T18-22-58Z
```

+ `cp local-docker-compose.yaml docker-compose.yaml`
+ `docker-compose up` (Note configured `JUPYTER_PASSWORD`)
+ Select a means of running MATLAB e.g. Jupyter Notebook, GUI, or Terminal (see bottom)
+ Add `tests` directory to path e.g. in MATLAB, `addpath('tests')`
+ Run desired tests. Some examples are as follows:

| Use Case                     | MATLAB Code                                                                    |
| ---------------------------- | ------------------------------------------------------------------------------ |
| Run all tests                | `run(Main)`                                                              |
| Run one class of tests       | `run(TestTls)`                                                           |
| Run one specific test        | `runtests('TestTls/TestTls_testInsecureConn')`                                   |
| Run tests based on test name | `import matlab.unittest.TestSuite;`<br>`import matlab.unittest.selectors.HasName;`<br>`import matlab.unittest.constraints.ContainsSubstring;`<br>`suite = TestSuite.fromClass(?Main, ... `<br><code>&nbsp;&nbsp;&nbsp;&nbsp;</code>`HasName(ContainsSubstring('Conn')));`<br>`run(suite)`|

### Launch Jupyter Notebook

+ Navigate to `localhost:8888`
+ Input Jupyter password
+ Launch a notebook i.e. `New > MATLAB`

### Launch MATLAB GUI (supports remote interactive debugger)

+ Shell into `datajoint-matlab_app_1` i.e. `docker exec -it datajoint-matlab_app_1 bash`
+ Launch Matlab by running command `matlab`

### Launch MATLAB Terminal

+ Shell into `datajoint-matlab_app_1` i.e. `docker exec -it datajoint-matlab_app_1 bash`
+ Launch Matlab with no GUI by running command `matlab -nodisplay`

</details>

## Parent-key SELECT optimization

Fetches, existence checks, and counts can accelerate simple key restrictions
through an indexed parent. For example, scalar `etag` and `subject` equalities
on an epoch-channel table can also restrict its epoch parent, allowing keyed
access to the child instead of scanning its full primary index.

This is enabled by default. To disable it:

```matlab
dj.config('queryParentKeyOptimization', false)
```

The first implementation handles scalar structs and individual SQL
`key = literal` conditions on base tables. It requires an unrenamed,
nonnullable primary foreign key covering the parent's primary key, a known
leading parent index column, and an unambiguous best parent. It keeps the
original child predicates and adds a redundant parent semijoin. Compound SQL,
functions, negations, struct-array disjunctions, and uncertain mappings are
left unchanged. Parent indexes are identified from primary and foreign-key
metadata; custom secondary indexes are not inspected.

Rewriting applies only during SELECT compilation, including beneath
projections and joins. Raw `rel.sql` and write predicates retain their original
form. This feature does not create indexes or modify database data. Schema
metadata reloads are used directly; there is no cached query-plan choice.

Metadata-only regression tests can be run with:

```matlab
addpath('tests')
results = runtests('TestParentKeyOptimization');
assertSuccess(results)
```
