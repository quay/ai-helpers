FROM golang:1.26 AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY event.go ./
COPY webhook-router/ ./webhook-router/

RUN CGO_ENABLED=0 go build -o /webhook-router ./webhook-router/

FROM registry.access.redhat.com/ubi9-micro:latest
COPY --from=builder /webhook-router /webhook-router
ENTRYPOINT ["/webhook-router"]
