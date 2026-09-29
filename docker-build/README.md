# docker-build

Builds a docker image using BuildKit. For PRs and commits, the build targets are:

- `test-results` - This includes running the tests in docker and capturing the expected artifacts
- `integration-test` - Verifies the test results and is capable of testing against other environments
- The final target - The application image target

Additionally:

- Checks a provided status file to skip the build if specified.
- For commits, the final and `integration-test` targets are pushed
