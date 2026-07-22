// Temporary diagnostic: check each layer of the deployed bus ETA path.
// MRT eta (control), MaaS plan (to obtain a real SubRouteUID), then bus
// static / daily timetable (DB+Redis static path) and the two bus ETA
// streams (Redis live path). Not for commit.
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"

	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
)

func main() {
	conn, err := grpc.NewClient("192.168.0.131:50051",
		grpc.WithTransportCredentials(credentials.NewTLS(
			&tls.Config{InsecureSkipVerify: true})))
	if err != nil {
		panic(err)
	}
	defer conn.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Control: MRT live path.
	mctx, mcancel := context.WithTimeout(ctx, 8*time.Second)
	if s, err := pb.NewMrt_ServiceClient(conn).Eta(mctx, &pb.AskMrt{System: "TRTC", StationID: "BL12"}); err != nil {
		fmt.Println("mrt call error:", err)
	} else if m, err := s.Recv(); err != nil {
		fmt.Println("mrt recv error:", err)
	} else {
		fmt.Printf("mrt ok: station=%s est=%d\n", m.GetData().GetStationID(), m.GetData().GetEstimateTime())
	}
	mcancel()

	// Get a real bus SubRouteUID out of a MaaS plan.
	resp, err := pb.NewMaasServiceClient(conn).Plan(ctx, &pb.MaasPlanRequest{
		FromLat: 25.0330, FromLon: 121.5654,
		ToLat: 25.0478, ToLon: 121.5170,
		Date: time.Now().Format("2006-01-02"),
		Time: time.Now().Add(10 * time.Minute).Format("15:04"),
	})
	if err != nil {
		fmt.Println("maas plan error:", err)
		return
	}
	var busUID string
	for _, r := range resp.GetRoutes() {
		for _, s := range r.GetSections() {
			ni := s.GetNotificationIdentity()
			if ni.GetRouteType() == "bus" && ni.GetRouteKey() != "" {
				busUID = ni.GetRouteKey()
			}
			fmt.Printf("section type=%s route_type=%s route_key=%s\n",
				s.GetType(), ni.GetRouteType(), ni.GetRouteKey())
		}
	}
	if busUID == "" {
		fmt.Println("no bus section in plan; cannot derive SubRouteUID")
		return
	}
	fmt.Println("probing bus uid:", busUID)

	rc := pb.NewBus_Route_ServiceClient(conn)

	// Static path: DB-backed.
	if st, err := rc.Static(ctx, &pb.Bus_Ask_Route{SubRouteUID: busUID}); err != nil {
		fmt.Println("bus static error:", err)
	} else {
		fmt.Printf("bus static ok: route=%s dirs=%d\n", st.GetData().GetRouteName(), len(st.GetData().GetDirections()))
	}

	// Daily timetable: Redis-backed static load.
	if tt, err := rc.Daily(ctx, &pb.Bus_Ask_Route{SubRouteUID: busUID}); err != nil {
		fmt.Println("bus daily error:", err)
	} else {
		fmt.Printf("bus daily ok: tables=%v\n", tt.GetData() != nil)
	}

	// Live path: Redis ETA snapshot + pub/sub.
	ectx, ecancel := context.WithTimeout(ctx, 40*time.Second)
	defer ecancel()
	if es, err := rc.Eta(ectx, &pb.Bus_Ask_Route{SubRouteUID: busUID}); err != nil {
		fmt.Println("bus eta call error:", err)
	} else if m, err := es.Recv(); err != nil {
		fmt.Println("bus eta recv error:", err)
	} else {
		fmt.Printf("bus eta ok: stops=%d\n", len(m.GetData().GetStops()))
	}
}
