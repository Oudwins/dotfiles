package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"sync"
)

type lockStore struct {
	mu     sync.Mutex
	path   string
	locked map[string]bool
}

func loadLocks(path string) (*lockStore, error) {
	store := &lockStore{path: path, locked: make(map[string]bool)}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return store, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read schedule locks: %w", err)
	}
	if err := json.Unmarshal(data, &store.locked); err != nil || store.locked == nil {
		return nil, errors.New("invalid schedule lock state; refusing to silently unlock routers")
	}
	return store, nil
}

func (s *lockStore) get(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.locked[id]
}

func (s *lockStore) set(id string, locked bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.locked[id] == locked {
		return nil
	}
	next := maps.Clone(s.locked)
	if locked {
		next[id] = true
	} else {
		delete(next, id)
	}
	data, err := json.MarshalIndent(next, "", "  ")
	if err != nil {
		return err
	}
	directory := filepath.Dir(s.path)
	if err := os.MkdirAll(directory, 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(directory, ".locks-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	defer file.Close()
	if _, err := file.Write(append(data, '\n')); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(file.Name(), s.path); err != nil {
		return err
	}
	s.locked = next
	return nil
}
