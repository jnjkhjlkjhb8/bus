package shared

import (
	"os"
	"testing"
	"time"

	"github.com/go-redis/redis"
)

// TestConnectRedis_WithPassword dials a real Redis started with --requirepass
// and proves the Go client authenticates successfully with a password, the
// same Options shape ConnectRedis builds from REDIS_ADDR/REDIS_PASSWORD.
// REDIS_AUTH_TEST_ADDR names a Redis reachable with REDIS_AUTH_TEST_PASSWORD;
// unset means "no requirepass Redis promised" and the test skips (mirrors the
// REDIS_TEST_ADDR skip pattern used elsewhere in this repo for optional
// live-Redis integration tests). Start one locally with:
//
//	docker run --rm -p 16380:6379 redis:7-alpine redis-server --requirepass s3cret
//	REDIS_AUTH_TEST_ADDR=127.0.0.1:16380 REDIS_AUTH_TEST_PASSWORD=s3cret go test ./services/shared/... -run TestConnectRedis_WithPassword
func TestConnectRedis_WithPassword(t *testing.T) {
	addr := envOrSkip(t, "REDIS_AUTH_TEST_ADDR")
	password := envOrSkip(t, "REDIS_AUTH_TEST_PASSWORD")

	client := redis.NewClient(&redis.Options{Addr: addr, Password: password})
	t.Cleanup(func() { _ = client.Close() })

	deadline := time.Now().Add(5 * time.Second)
	var pong string
	var err error
	for {
		pong, err = client.Ping().Result()
		if err == nil || time.Now().After(deadline) {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if err != nil {
		t.Fatalf("PING against password-protected Redis failed: %v", err)
	}
	if pong != "PONG" {
		t.Fatalf("PING reply = %q, want PONG", pong)
	}

	// A client that sends the wrong password must be rejected — proves the
	// server actually enforces requirepass rather than the test dialing an
	// unauthenticated Redis by accident.
	wrong := redis.NewClient(&redis.Options{Addr: addr, Password: "definitely-not-the-password"})
	t.Cleanup(func() { _ = wrong.Close() })
	if _, err := wrong.Ping().Result(); err == nil {
		t.Fatal("PING with wrong password unexpectedly succeeded")
	}
}

func envOrSkip(t *testing.T, name string) string {
	t.Helper()
	v := os.Getenv(name)
	if v == "" {
		t.Skipf("%s not set", name)
	}
	return v
}
