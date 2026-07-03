# Build context: ./docker-compose.yaml
# docker build -f server/functions/Dockerfile -t wheres_the_car-functions .

FROM golang:1.26.3-alpine3.23 AS builder
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
COPY server/obs/ ./server/obs/
COPY server/functions/ ./server/functions/
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o functions ./server/functions
FROM alpine:3.23
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /root/
COPY --from=builder /app/functions .
ENTRYPOINT ["./functions"]
