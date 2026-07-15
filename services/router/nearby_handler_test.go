package main

import (
	"context"
	"errors"
	"io"
	"math"
	"testing"

	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

type fakeNearStream struct {
	request  *pb.Ask_Near
	received bool
}

type panicNearbyStore struct{}

func (panicNearbyStore) Find(context.Context, nearbyMode, nearbyQuery) ([]nearbyCandidate, error) {
	panic("nearby store must not be called for an invalid query")
}

func (s *fakeNearStream) Send(*pb.RespNear) error { return nil }
func (s *fakeNearStream) Recv() (*pb.Ask_Near, error) {
	if s.received {
		return nil, io.EOF
	}
	s.received = true
	return s.request, nil
}
func (s *fakeNearStream) SetHeader(metadata.MD) error  { return nil }
func (s *fakeNearStream) SendHeader(metadata.MD) error { return nil }
func (s *fakeNearStream) SetTrailer(metadata.MD)       {}
func (s *fakeNearStream) Context() context.Context     { return context.Background() }
func (s *fakeNearStream) SendMsg(any) error            { return nil }
func (s *fakeNearStream) RecvMsg(any) error            { return nil }

func TestFindNearMapsTotalDiscoveryFailureToUnavailable(t *testing.T) {
	failures := map[nearbyMode]error{}
	for _, mode := range allNearbyModes {
		failures[mode] = errors.New("query failed")
	}
	server := &Near_Server{discovery: newNearbyDiscovery(
		fakeNearbyStore{rows: map[nearbyMode][]nearbyCandidate{}, err: failures},
		&fakeWalkingRouter{},
	)}

	err := server.FindNear(&fakeNearStream{request: &pb.Ask_Near{PositionLon: 121.5, PositionLat: 25, Radius: 500}})
	if status.Code(err) != codes.Unavailable {
		t.Fatalf("code = %s, err = %v, want Unavailable", status.Code(err), err)
	}
}

func TestFindNearRejectsInvalidQuery(t *testing.T) {
	server := &Near_Server{discovery: newNearbyDiscovery(panicNearbyStore{}, nil)}

	err := server.FindNear(&fakeNearStream{request: &pb.Ask_Near{
		PositionLon: math.Inf(1), PositionLat: 25, Radius: 500,
	}})
	if status.Code(err) != codes.InvalidArgument {
		t.Fatalf("code = %s, err = %v, want InvalidArgument", status.Code(err), err)
	}
}
