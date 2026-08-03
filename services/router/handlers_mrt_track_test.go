package main

import (
	"context"
	"testing"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

// undirectedAdjacency builds a both-directions map the way the loader stores
// mrt_adjacency, so BFS walks it as an undirected line graph.
func undirectedAdjacency(edges [][2]string) map[string][]string {
	adjacency := map[string][]string{}
	for _, e := range edges {
		adjacency[e[0]] = append(adjacency[e[0]], e[1])
		adjacency[e[1]] = append(adjacency[e[1]], e[0])
	}
	return adjacency
}

func TestMrtBFSPath(t *testing.T) {
	// A line with a branch at O13: main O12→O13→O14, branch O13→O50.
	adjacency := undirectedAdjacency([][2]string{
		{"O12", "O13"}, {"O13", "O14"}, {"O13", "O50"},
	})
	cases := []struct {
		name        string
		board, term string
		want        []string
		wantOK      bool
	}{
		{"linear", "O12", "O14", []string{"O12", "O13", "O14"}, true},
		{"branch", "O12", "O50", []string{"O12", "O13", "O50"}, true},
		{"reverse", "O14", "O12", []string{"O14", "O13", "O12"}, true},
		{"same station", "O12", "O12", nil, false},
		{"unreachable other line", "O12", "BL15", nil, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := mrtBFSPath(adjacency, c.board, c.term)
			if ok != c.wantOK {
				t.Fatalf("ok = %v want %v", ok, c.wantOK)
			}
			if !equalStrings(got, c.want) {
				t.Errorf("path = %v want %v", got, c.want)
			}
		})
	}
}

func TestMrtTargetIndex(t *testing.T) {
	path := []string{"O12", "O13", "O14", "O15"}
	cases := []struct {
		target string
		want   int32
		ok     bool
	}{
		{"O13", 1, true},
		{"O15", 3, true},
		{"O12", 0, false}, // the board itself is not "ahead"
		{"O99", 0, false}, // not on the path
	}
	for _, c := range cases {
		got, ok := mrtTargetIndex(path, c.target)
		if got != c.want || ok != c.ok {
			t.Errorf("mrtTargetIndex(%q) = %d,%v want %d,%v", c.target, got, ok, c.want, c.ok)
		}
	}
}

func TestCreateTrackValidation(t *testing.T) {
	server := &MrtServer{}
	base := &pb.CreateMrtTrackRequest{
		InstallId: "install-1", CarId: "1021", BoardStationId: "BL12",
		DestStationId: "BL17", TargetStationId: "BL15", LeadStops: 2, System: "TRTC",
	}
	clone := func(mutate func(*pb.CreateMrtTrackRequest)) *pb.CreateMrtTrackRequest {
		r := proto.Clone(base).(*pb.CreateMrtTrackRequest)
		mutate(r)
		return r
	}
	cases := []struct {
		name string
		req  *pb.CreateMrtTrackRequest
		code codes.Code
	}{
		{"missing car", clone(func(r *pb.CreateMrtTrackRequest) { r.CarId = "" }), codes.InvalidArgument},
		{"missing target", clone(func(r *pb.CreateMrtTrackRequest) { r.TargetStationId = "" }), codes.InvalidArgument},
		{"non-TRTC system", clone(func(r *pb.CreateMrtTrackRequest) { r.System = "KRTC" }), codes.FailedPrecondition},
		{"lead too low", clone(func(r *pb.CreateMrtTrackRequest) { r.LeadStops = -1 }), codes.InvalidArgument},
		{"lead too high", clone(func(r *pb.CreateMrtTrackRequest) { r.LeadStops = 121 }), codes.InvalidArgument},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := server.CreateTrack(context.Background(), c.req)
			if status.Code(err) != c.code {
				t.Errorf("CreateTrack() code = %v want %v (err=%v)", status.Code(err), c.code, err)
			}
		})
	}
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
