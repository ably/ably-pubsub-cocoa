# Tools for investigating test failures

In order to work on stabilising our test suite in ably/ably-cocoa#1279, we need to be able to:

- understand why a particular test case is failing
- check whether an attempted fix for a failing test case has worked

## Look at the existing failures

We've already run the tests many times and gathered lots of data about failing tests, so you might be able to make use of the existing data by finding the test case on the [test observability server](https://test-observability.herokuapp.com/repos/ably/ably-cocoa/uploads/) (see the "Occurrences of failures" table at the bottom of the linked page) and looking through its failures.

You should probably use the [branch filter](https://test-observability.herokuapp.com/repos/ably/ably-cocoa/uploads/filter) to only look at results from the `main`, `1279-run-tests-in-loop`, and `1279-run-tests-in-loop-lots-of-times` branches, unless there's a particular feature branch you want to look at for some reason.

### Finding out more about the reason for a crashed test

As of [`5cc6f06`](https://github.com/ably/ably-cocoa/commit/5cc6f067f567ad77fafbdfd6f8999e1dd05f8c7a), each test run will also upload the crash reports for any crashes that occurred during that run. These crash reports can be viewed on the failure details page; [here](https://test-observability.herokuapp.com/repos/ably/ably-cocoa/failures/c3a3db1c-6c7c-4e46-b8ab-a344a0b70ee0) is an example.

## Add further diagnostic information to the test suite

If the existing logs don't give you much information about what's causing a failure, or if you want to investigate some hypothesis, you might want to:

- add further log statements to the test suite or SDK
- increase the logging level of the SDK for a particular test case - you can do this, for example, by passing the `debug: true` parameter to [`AblyTests.commonAppSetup`](../Test/AblyTests/Test%20Utilities/TestUtilities.swift#L176) which will turn on verbose logging in the created `ClientOptions`
    - It's worth mentioning that increasing the log level seems to interfere with some tests – I found out that [turning on verbose logging for the entire test suite](https://test-observability.herokuapp.com/repos/ably/ably-cocoa/uploads?branches%5B%5D=1279-run-in-loop-with-extra-logging&createdBefore=&createdAfter=&failureMessage=) seemed to introduce test failures I'd not seen before.
- try running a particular test case in isolation by disabling all other tests

You can then [run the tests in a loop](#running-the-tests-in-a-loop) on your feature branch and take a look at the results.

## Running the tests in a loop

We have a branch [`1279-run-tests-in-loop`](https://github.com/ably/ably-cocoa/tree/1279-run-tests-in-loop), which has been modified so that:

- only the iOS CI job runs
- the ably-cocoa test suite [runs continuously in a loop](https://github.com/ably/ably-cocoa/blob/1279-run-tests-in-loop/Scripts/continuously-run-tests-and-upload-results.sh) — it will stop itself after approximately 5hr 45min, to stop it from being killed by GitHub after 6 hours
- the full `xcodebuild` logs (including the test suite logs) are printed to the CI job log after each loop iteration
- the test results are uploaded to the test observability server after each loop iteration

So, if you want to observe how a test case is behaving when run multiple times (perhaps after adding further logging to it, or after trying to fix it):

1. Merge `1279-run-tests-in-loop` into your feature branch.
2. Push to GitHub and open a draft pull request. This will cause CI to run on that branch. If you want more than 6 hours' worth of test results, you will need to re-run the failed job manually, or see how to [run the tests for a long time or in parallel](#running-for-a-long-time-or-in-parallel).

You can then use the [branch filter](https://test-observability.herokuapp.com/repos/ably/ably-cocoa/uploads/filter) in the test observability server to view all of the test results from your branch. If you are seeing failures that you'd like to investigate further, [we also have a script](#downloading-all-of-the-xcodebuild-logs-for-a-branch) that you can use to download all the `xcodebuild` logs for that branch.

### Running for a long time or in parallel

If you'd like to run the tests for more than 6 hours, or would to perform multiple test runs in parallel, you can use the script [`Scripts/set-ci-length-and-parallelism.sh`](https://github.com/ably/ably-cocoa/blob/1279-run-tests-in-loop/Scripts/set-ci-length-and-parallelism.sh). This script will modify / create extra GitHub workflow YAML files to allow you to increase the number of workflows and jobs per workflow. See the usage instructions in the script.

### Downloading all of the `xcodebuild` logs for a branch

The aforementioned branch `1279-run-tests-in-loop` has a script, [`fetch-test-logs.sh`](https://github.com/ably/ably-cocoa/blob/1279-run-tests-in-loop/Scripts/fetch-test-logs.sh), which allows you to fetch the `xcodebuild` logs for one or more observability server uploads.

The best source of documentation is the script itself, but to give an overview, you can either:

- Download the logs for a single upload using the `--upload-id` option;
- Download the logs for all uploads matching a certain filter, specified by the `--filter` option, for example `--filter 'branches[]=my-branch-name'`. Given a test case ID (specified by `--test-case-id`), the script will save the logs into two separate directories, depending on whether the given test case succeeded or failed in that upload. This makes it easy to, for example, check whether a particular log line appears in all failures and none of the successes.
    - The easiest way to get a `--filter` parameter is to use the test observability server's [filtering UI](https://test-observability.herokuapp.com/repos/ably/ably-cocoa/uploads/filter) and then copy the query string from the resulting URL.

## Testing out a fix

If you think that you've fixed a failing test, you'll want to confirm this. Furthermore, you'll want to confirm that you've not accidentally introduced other failures. One way to do this would be to run the tests a decent number of times on the feature branch containing your fix, and to then compare these results to the results from `main`.

The observability server has a comparison feature (see "Compare with another set of results" link on uploads overview page) that will help with this. For example, [here's](https://test-observability.herokuapp.com/repos/ably/ably-cocoa/uploads/compare?base-branches%5B%5D=1279-run-tests-in-loop&base-branches%5B%5D=1279-run-tests-in-loop-lots-of-times&base-branches%5B%5D=main&alternative-branches%5B%5D=1322-fix-test-case-4f837671-6233-41f1-94e8-01174d1da7b8&alternative-createdBefore=&alternative-createdAfter=&alternative-failureMessage=) the comparison for an attempted fix, from which you can see:

- Under "Failures absent in alternative uploads": shows that test case `4f837671-6233-41f1-94e8-01174d1da7b8` is no longer failing, which was the aim of this fix;
- Under "Failures introduced in alternative uploads": shows that the fix has introduced many new failures, and hence needs to be revisited.
