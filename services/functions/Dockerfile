# Build context: ./docker-compose.yaml
# docker build -f services/functions/Dockerfile -t wheres_the_car-functions .

FROM golang:1.26.3-alpine3.23@sha256:91eda9776261207ea25fd06b5b7fed8d397dd2c0a283e77f2ab6e91bfa71079d AS builder
RUN apk add --no-cache git protobuf-dev
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
ENV PATH $PATH:/go/bin
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
COPY models/ ./models/
RUN protoc --go_out=paths=source_relative:models \
           --go-grpc_out=paths=source_relative:models \
           -I models models/*.proto
COPY services/obs/ ./services/obs/
COPY services/shared/ ./services/shared/
COPY services/functions/ ./services/functions/
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o functions ./services/functions

FROM alpine:3.23@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g 10001 app && \
    adduser -D -u 10001 -G app -h /home/app app
WORKDIR /home/app
COPY --from=builder --chown=app:app /app/functions .
USER app:app
ENTRYPOINT ["./functions"]
