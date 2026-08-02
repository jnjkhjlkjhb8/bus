package main

import (
	"testing"
	"time"
)

func TestTTLCacheStoreAndGet(t *testing.T) {
	c := NewTTLCache()
	c.set("k", []byte("v"), time.Minute)
	got, ok := c.get("k")
	if !ok || string(got) != "v" {
		t.Fatalf("get() = (%q, %v), want (\"v\", true)", got, ok)
	}
}

func TestTTLCacheMiss(t *testing.T) {
	c := NewTTLCache()
	if _, ok := c.get("absent"); ok {
		t.Fatalf("get(absent) ok = true, want false")
	}
}

func TestTTLCacheExpiry(t *testing.T) {
	c := NewTTLCache()
	c.set("k", []byte("v"), -time.Second)
	if _, ok := c.get("k"); ok {
		t.Fatalf("expired entry returned ok = true, want false")
	}
}

// TestBoundedTTLCacheDropsEntriesPastTheCap: entries only ever expire when
// something asks for them again, so a cache keyed by user input would hold
// every one-off query forever without this.
func TestBoundedTTLCacheDropsEntriesPastTheCap(t *testing.T) {
	c := NewBoundedTTLCache(2)
	c.set("a", []byte("1"), time.Minute)
	c.set("b", []byte("2"), time.Minute)
	if _, ok := c.get("a"); !ok {
		t.Fatal("entry dropped before the cap was exceeded")
	}
	c.set("c", []byte("3"), time.Minute)
	for _, key := range []string{"a", "b", "c"} {
		if _, ok := c.get(key); ok {
			t.Fatalf("get(%q) ok = true, want the whole cache flushed past the cap", key)
		}
	}
	// The counter has to come back with it, or the next cap is reached
	// after a single write.
	c.set("d", []byte("4"), time.Minute)
	if _, ok := c.get("d"); !ok {
		t.Fatal("cache did not accept entries after a flush")
	}
}

// TestBoundedTTLCacheCountsDistinctKeys: overwriting a key must not push
// the cache toward a flush, or a hot key alone would keep clearing it.
func TestBoundedTTLCacheCountsDistinctKeys(t *testing.T) {
	c := NewBoundedTTLCache(2)
	for range 5 {
		c.set("same", []byte("v"), time.Minute)
	}
	if _, ok := c.get("same"); !ok {
		t.Fatal("repeated writes to one key flushed the cache")
	}
}
