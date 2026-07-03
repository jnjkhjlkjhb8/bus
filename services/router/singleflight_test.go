package main

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestFetchOnce_CollapsesConcurrentMisses(t *testing.T) {
	var calls int32
	start := make(chan struct{})
	var ready sync.WaitGroup
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		ready.Add(1)
		wg.Add(1)
		go func() {
			defer wg.Done()
			ready.Done()
			<-start
			fetchOnce("k1", func() {
				atomic.AddInt32(&calls, 1)
				time.Sleep(50 * time.Millisecond)
			})
		}()
	}
	ready.Wait()
	close(start)
	wg.Wait()
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("expected 1 fetch, got %d", got)
	}
}
