package main

import (
	"testing"
	"time"
)

func TestTTLCacheStoreAndGet(t *testing.T) {
	c := newTTLCache()
	c.set("k", []byte("v"), time.Minute)
	got, ok := c.get("k")
	if !ok || string(got) != "v" {
		t.Fatalf("get() = (%q, %v), want (\"v\", true)", got, ok)
	}
}

func TestTTLCacheMiss(t *testing.T) {
	c := newTTLCache()
	if _, ok := c.get("absent"); ok {
		t.Fatalf("get(absent) ok = true, want false")
	}
}

func TestTTLCacheExpiry(t *testing.T) {
	c := newTTLCache()
	c.set("k", []byte("v"), -time.Second)
	if _, ok := c.get("k"); ok {
		t.Fatalf("expired entry returned ok = true, want false")
	}
}
