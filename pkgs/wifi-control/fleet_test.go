package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

type recordingController struct {
	mu      sync.Mutex
	enabled bool
	calls   int
	writes  int
	err     error
}

func (c *recordingController) operate(ctx context.Context, desired *bool) (Result, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.calls++
	if c.err != nil {
		return Result{}, c.err
	}
	changed := desired != nil && *desired != c.enabled
	if changed {
		c.enabled = *desired
		c.writes++
	}
	return Result{Radios: []Radio{{ID: "radio0", Band: "2.4GHz", Enabled: c.enabled}}, Changed: changed}, nil
}

func testFleet(t *testing.T) (*fleet, *recordingController, *recordingController) {
	t.Helper()
	locks, err := loadLocks(filepath.Join(t.TempDir(), "locks.json"))
	if err != nil {
		t.Fatal(err)
	}
	f := newFleet(serviceConfig{Routers: map[string]routerConfig{"digi": {Name: "DIGI"}, "openwrt": {Name: "OpenWrt"}}}, locks)
	a, b := &recordingController{enabled: true}, &recordingController{enabled: true}
	f.routers["digi"].controller, f.routers["openwrt"].controller = a, b
	return f, a, b
}

func TestScheduleLocksAndManualCommands(t *testing.T) {
	f, digi, openwrt := testFleet(t)
	ctx := context.Background()
	if err := f.setLock(ctx, "openwrt", true); err != nil {
		t.Fatal(err)
	}
	results, failed := f.scheduled(ctx, false)
	if failed || digi.enabled || !openwrt.enabled || !results[1].Skipped || openwrt.calls != 0 {
		t.Fatalf("locked router was contacted: %+v", results)
	}
	off := false
	if _, err := f.operate(ctx, "openwrt", &off, false); err != nil || openwrt.enabled {
		t.Fatal("manual command did not work while locked", err)
	}
	_, failed = f.scheduled(ctx, true)
	if failed || !digi.enabled || openwrt.enabled {
		t.Fatal("morning timer did not respect the lock")
	}
	if err := f.setLock(ctx, "openwrt", false); err != nil || openwrt.enabled {
		t.Fatal("unlock changed radio state", err)
	}
	if _, err := f.operate(ctx, "openwrt", nil, false); err != nil || openwrt.enabled {
		t.Fatal("status polling changed radio state", err)
	}
	_, failed = f.scheduled(ctx, true)
	if failed || !openwrt.enabled {
		t.Fatal("next timer did not resume control")
	}
}

func TestOneFailureDoesNotBlockOtherRouters(t *testing.T) {
	f, digi, openwrt := testFleet(t)
	digi.err = errors.New("offline")
	results, failed := f.scheduled(context.Background(), false)
	if !failed || results[0].Error == "" || openwrt.enabled || openwrt.writes != 1 {
		t.Fatalf("other router was not processed: %+v", results)
	}
}

func TestLocksPersistAndUnlockIsAtomic(t *testing.T) {
	f, _, _ := testFleet(t)
	if err := f.setLock(context.Background(), "digi", true); err != nil {
		t.Fatal(err)
	}
	restored, err := loadLocks(f.locks.path)
	if err != nil || !restored.get("digi") {
		t.Fatal("lock did not survive restart", err)
	}
	info, err := os.Stat(f.locks.path)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("lock state permissions are not private")
	}
	// Make the destination unwritable as a file; failed persistence must not unlock in memory.
	blocked := filepath.Join(t.TempDir(), "directory")
	if err := os.Mkdir(blocked, 0700); err != nil {
		t.Fatal(err)
	}
	restored.path = blocked
	if err := restored.set("digi", false); err == nil || !restored.get("digi") {
		t.Fatal("failed write silently unlocked router")
	}
	if err := os.WriteFile(f.locks.path, []byte("broken JSON"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadLocks(f.locks.path); err == nil {
		t.Fatal("corrupt state was silently discarded")
	}
}

type blockingController struct {
	started chan struct{}
	release chan struct{}
}

func (b *blockingController) operate(ctx context.Context, desired *bool) (Result, error) {
	close(b.started)
	select {
	case <-b.release:
		return Result{}, nil
	case <-ctx.Done():
		return Result{}, ctx.Err()
	}
}

func TestLockAndScheduledWriteAreSerialized(t *testing.T) {
	f, _, _ := testFleet(t)
	b := &blockingController{started: make(chan struct{}), release: make(chan struct{})}
	f.routers["digi"].controller = b
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		off := false
		_, _ = f.operate(context.Background(), "digi", &off, true)
	}()
	<-b.started
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := f.setLock(ctx, "digi", true); err != context.DeadlineExceeded {
		t.Fatal("lock was acknowledged while a router command was still running", err)
	}
	close(b.release)
	<-finished
	if err := f.setLock(context.Background(), "digi", true); err != nil {
		t.Fatal(err)
	}
	off := false
	result, err := f.operate(context.Background(), "digi", &off, true)
	if err != nil || !result.Skipped {
		t.Fatal("scheduled write ignored an acknowledged lock")
	}
}
