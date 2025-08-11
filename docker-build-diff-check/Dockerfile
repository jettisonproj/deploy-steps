# Skip integration test for deploy steps
# Instead, it should be covered by the caller
FROM scratch as integration-test

# Build the image for the deploy step
FROM ubuntu:24.04
RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get -y install software-properties-common && \
  add-apt-repository -y ppa:git-core/ppa && \
  apt-get update && \
  apt-get -y install git && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

WORKDIR /root

COPY docker-build-diff-check-pr.sh docker-build-diff-check-commit.sh .

CMD ["./docker-build-diff-check-pr.sh"]
