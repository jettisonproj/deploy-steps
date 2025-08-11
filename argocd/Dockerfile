# Skip integration test for deploy steps
# Instead, it should be covered by the caller
FROM scratch as integration-test

# Build the image for the deploy step
FROM ubuntu:24.04
RUN apt-get update && \
  apt-get -y install curl git jq && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives && \
  curl -LsSfO "https://dl.k8s.io/release/$(curl -LsSf https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
  chmod +x ./kubectl && \
  mv kubectl /usr/local/bin && \
  ARGOCD_CLI_VERSION=$(curl -LsSf https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION) && \
  curl -LsSf -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$ARGOCD_CLI_VERSION/argocd-linux-amd64 && \
  install -m 555 argocd-linux-amd64 /usr/local/bin/argocd && \
  rm argocd-linux-amd64

WORKDIR /root

COPY generate-github-installation-access-token.sh wait-for-resource.sh git-push.sh deploy-step-argocd.sh .

CMD ["./deploy-step-argocd.sh"]
