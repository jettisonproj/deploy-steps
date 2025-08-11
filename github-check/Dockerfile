# Skip integration test for deploy steps
# Instead, it should be covered by the caller
FROM scratch as integration-test

# Build the image for the deploy step
FROM ubuntu:24.04
RUN apt-get update && \
  apt-get -y install curl jq && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

WORKDIR /root

COPY generate-github-installation-access-token.sh github-check-start.sh github-check-complete.sh .

CMD ["./deploy-step-github-check.sh"]
