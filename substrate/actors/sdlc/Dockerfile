FROM golang:1.26 AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY event.go ./
COPY actors/sdlc/ ./actors/sdlc/

RUN CGO_ENABLED=0 go build -o /sdlc-actor ./actors/sdlc/

FROM registry.access.redhat.com/ubi9-minimal:latest
RUN microdnf install -y git && microdnf clean all
COPY --from=builder /sdlc-actor /sdlc-actor
ENTRYPOINT ["/sdlc-actor"]
