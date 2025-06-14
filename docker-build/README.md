# docker-build

This builds a docker image using Kaniko. For PRs, all layers are built.
For commits, all layers are built and pushed.

Also checks a provided status file to skip the build if specified.
