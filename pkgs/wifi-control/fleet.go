package main

import (
	"context"
	"errors"
	"log/slog"
	"slices"
	"sync"
)

var errUnknownRouter = errors.New("unknown router ID")

type routerInfo struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Type   string `json:"type"`
	URL    string `json:"url"`
	Locked bool   `json:"locked"`
}

type routerResult struct {
	Result
	ID      string `json:"id"`
	Locked  bool   `json:"locked"`
	Skipped bool   `json:"skipped,omitempty"`
	Error   string `json:"error,omitempty"`
}

type managedRouter struct {
	info       routerInfo
	controller radioController
	gate       chan struct{}
}

type fleet struct {
	routers map[string]*managedRouter
	ids     []string
	locks   *lockStore
}

func newFleet(config serviceConfig, locks *lockStore) *fleet {
	f := &fleet{routers: make(map[string]*managedRouter), locks: locks}
	for id, router := range config.Routers {
		f.ids = append(f.ids, id)
		f.routers[id] = &managedRouter{
			info:       routerInfo{ID: id, Name: router.Name, Type: router.Type, URL: router.URL},
			controller: configuredController{config: router}, gate: make(chan struct{}, 1),
		}
	}
	slices.Sort(f.ids)
	return f
}

func (f *fleet) list() []routerInfo {
	items := make([]routerInfo, 0, len(f.ids))
	for _, id := range f.ids {
		info := f.routers[id].info
		info.Locked = f.locks.get(id)
		items = append(items, info)
	}
	return items
}

func (r *managedRouter) acquire(ctx context.Context) error {
	select {
	case r.gate <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (f *fleet) operate(ctx context.Context, id string, desired *bool, scheduled bool) (routerResult, error) {
	result := routerResult{ID: id, Locked: f.locks.get(id)}
	router, ok := f.routers[id]
	if !ok {
		return result, errUnknownRouter
	}
	if err := router.acquire(ctx); err != nil {
		return result, err
	}
	defer func() { <-router.gate }()
	// Lock changes and the scheduled check/write share this gate, so a successful
	// lock response cannot race a timer that has not yet sent its router command.
	result.Locked = f.locks.get(id)
	if scheduled && result.Locked {
		result.Skipped = true
		slog.Info("scheduled Wi-Fi command skipped", "router", id, "reason", "schedule locked")
		return result, nil
	}
	operation, err := router.controller.operate(ctx, desired)
	if err != nil {
		slog.Error("router operation failed", "router", id, "error", err)
		result.Error = "Could not confirm this router's state. Check its connection and credentials."
		if errors.Is(err, errCredentialsUnavailable) {
			result.Error = "Router credentials are unavailable. Configure them and restart the service."
		}
		return result, err
	}
	result.Result = operation
	if desired != nil {
		slog.Info("Wi-Fi command completed", "router", id, "enabled", *desired, "scheduled", scheduled, "changed", result.Changed)
	}
	return result, nil
}

func (f *fleet) setLock(ctx context.Context, id string, locked bool) error {
	router, ok := f.routers[id]
	if !ok {
		return errUnknownRouter
	}
	if err := router.acquire(ctx); err != nil {
		return err
	}
	defer func() { <-router.gate }()
	if err := f.locks.set(id, locked); err != nil {
		return err
	}
	slog.Info("schedule lock changed", "router", id, "locked", locked)
	return nil
}

func (f *fleet) scheduled(ctx context.Context, enabled bool) ([]routerResult, bool) {
	results := make([]routerResult, len(f.ids))
	var group sync.WaitGroup
	for index, id := range f.ids {
		group.Go(func() {
			result, err := f.operate(ctx, id, &enabled, true)
			if err != nil && result.Error == "" {
				result.Error = "The scheduled command could not complete."
			}
			results[index] = result
		})
	}
	group.Wait()
	failed := slices.ContainsFunc(results, func(result routerResult) bool { return result.Error != "" })
	return results, failed
}
