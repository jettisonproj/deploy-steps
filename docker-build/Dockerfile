# Skip integration test for deploy steps
# Instead, it should be covered by the caller
FROM scratch as integration-test

# Build the docker-build binary
FROM golang:1.24 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -o /docker-build

# Add the docker-build command to the buildkit image
FROM moby/buildkit:master-rootless
COPY --from=builder /docker-build /home/user/docker-build
ENTRYPOINT ["/home/user/docker-build"]
