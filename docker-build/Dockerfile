# Build the docker-build binary
FROM golang:1.24 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -o /docker-build

# Add the docker-build command to the kaniko image
FROM gcr.io/kaniko-project/executor:latest
COPY --from=builder /docker-build /kaniko/docker-build
ENTRYPOINT ["/kaniko/docker-build"]
