package main

import (
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

// DecodePayload unmarshals a cached inner-message payload (the raw bytes stored
// in Redis or the bus_static blob) into the typed response field T.
//
// Response envelopes carry field number 1 for their single message field, so
// wrapping the same inner bytes in the envelope is wire-equivalent to the former
// `bytes data = 1`. gRPC re-marshals every response on Send regardless, so this
// unmarshal is the only added cost and no manual field-1 framing is needed.
func DecodePayload[T proto.Message](data []byte, msg T) (T, error) {
	if err := proto.Unmarshal(data, msg); err != nil {
		return msg, status.Errorf(codes.Internal, "decode payload: %v", err)
	}
	return msg, nil
}
