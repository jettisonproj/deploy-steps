# docker-build-diff-check

This checks if a docker build is needed by detecting relevant file changes.

Additionally:

- Adds a status file with "Skipped" if no relevant files changed
- Adds override files to the clone directory after cloning
