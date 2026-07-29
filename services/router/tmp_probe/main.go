// Temporary diagnostic: call the deployed router's MaaS plan and report
// whether walk sections carry OSRM walkPath/walkSteps. Not for commit.
package main

import (
	"context"
	"fmt"
	"time"

	"crypto/tls"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
)

func main() {
	// Staging serves gRPC over TLS (GRPC_TLS=true); the cert is for the host's
	// own name, so skip verification for this one-off probe.
	conn, err := grpc.NewClient("192.168.0.131:50051",
		grpc.WithTransportCredentials(credentials.NewTLS(
			&tls.Config{InsecureSkipVerify: true})))
	if err != nil {
		panic(err)
	}
	defer func() { _ = conn.Close() }()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	resp, err := pb.NewMaasServiceClient(conn).Plan(ctx, &pb.MaasPlanRequest{
		FromLat: 25.0330, FromLon: 121.5654, // Taipei 101
		ToLat: 25.0478, ToLon: 121.5170, // Taipei Main Station
		Date: time.Now().Format("2006-01-02"),
		Time: time.Now().Add(10 * time.Minute).Format("15:04"),
	})
	if err != nil {
		fmt.Println("plan error:", err)
		return
	}
	fmt.Println("routes:", len(resp.Routes))
	for ri, r := range resp.Routes {
		for si, s := range r.Sections {
			mode := ""
			if s.Transport != nil {
				mode = s.Transport.Mode
			}
			fmt.Printf("route %d sec %d mode=%q dur=%d walkPath=%d walkSteps=%d\n",
				ri, si, mode, s.TravelSummary.GetDuration(),
				len(s.WalkPath), len(s.WalkSteps))
			for _, st := range s.WalkSteps[:min(2, len(s.WalkSteps))] {
				fmt.Printf("    step: %q %s/%s %.0fm\n",
					st.Instruction, st.ManeuverType, st.Modifier, st.DistanceMeters)
			}
		}
	}
}
