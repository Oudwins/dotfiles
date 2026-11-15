package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strings"
	"time"
)

type openWrt struct {
	endpoint string
	token    string
	username string
	password string
	client   *http.Client
}

func newOpenWrt(endpoint, token, username, password, fingerprint string) (*openWrt, error) {
	if err := validateRouterURL(endpoint, true); err != nil {
		return nil, err
	}
	client, err := routerHTTPClient(fingerprint)
	if err != nil {
		return nil, err
	}
	return &openWrt{endpoint: endpoint, token: token, username: username, password: password, client: client}, nil
}

func (r *openWrt) call(ctx context.Context, token, object, method string, args any) (json.RawMessage, error) {
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": "call",
		"params": []any{token, object, method, args},
	})
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := r.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("OpenWrt API request failed: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("OpenWrt API returned HTTP %d", response.StatusCode)
	}
	var reply struct {
		ID     int               `json:"id"`
		Result []json.RawMessage `json:"result"`
		Error  *struct {
			Code int `json:"code"`
		} `json:"error"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&reply); err != nil || reply.ID != 1 {
		return nil, errors.New("invalid OpenWrt API response")
	}
	if reply.Error != nil {
		if reply.Error.Code == -32002 {
			return nil, errors.New("OpenWrt API access denied: check token expiry and wireless permissions")
		}
		return nil, fmt.Errorf("OpenWrt API error %d", reply.Error.Code)
	}
	if len(reply.Result) == 0 {
		return nil, errors.New("missing OpenWrt API result")
	}
	var code *int
	if err := json.Unmarshal(reply.Result[0], &code); err != nil || code == nil {
		return nil, errors.New("OpenWrt returned an invalid ubus status")
	}
	if *code != 0 {
		return nil, fmt.Errorf("OpenWrt rejected %s.%s (ubus status %d)", object, method, *code)
	}
	if len(reply.Result) == 1 {
		return nil, nil
	}
	return reply.Result[1], nil
}

func (r *openWrt) operate(ctx context.Context, desired *bool) (Result, error) {
	token := r.token
	if token == "" {
		data, err := r.call(ctx, strings.Repeat("0", 32), "session", "login", map[string]any{
			"username": r.username, "password": r.password, "timeout": 300,
		})
		if err != nil {
			return Result{}, err
		}
		var session struct {
			Token string `json:"ubus_rpc_session"`
		}
		if err := json.Unmarshal(data, &session); err != nil || session.Token == "" {
			return Result{}, errors.New("OpenWrt login returned no session")
		}
		token = session.Token
		defer func() {
			logout, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			_, _ = r.call(logout, token, "session", "destroy", map[string]any{})
		}()
	}
	radios, err := r.radios(ctx, token)
	if err != nil {
		return Result{}, err
	}
	if desired == nil {
		return Result{Radios: radios}, nil
	}
	if *desired && !slices.ContainsFunc(radios, func(radio Radio) bool { return !radio.ConfiguredDisabled }) {
		return Result{}, errors.New("all radios are disabled in the OpenWrt configuration")
	}
	if openWrtMatches(radios, *desired) {
		return Result{Radios: radios}, nil
	}
	method := "down"
	if *desired {
		method = "up"
	}
	if _, err := r.call(ctx, token, "network.wireless", method, map[string]any{}); err != nil {
		return Result{}, err
	}
	for {
		radios, err = r.radios(ctx, token)
		if err != nil {
			return Result{}, err
		}
		if openWrtMatches(radios, *desired) {
			return Result{Radios: radios, Changed: true}, nil
		}
		select {
		case <-time.After(time.Second):
		case <-ctx.Done():
			return Result{}, errors.New("OpenWrt did not confirm the requested wireless state before timeout")
		}
	}
}

func openWrtMatches(radios []Radio, desired bool) bool {
	if len(radios) == 0 {
		return false
	}
	for _, radio := range radios {
		if desired && radio.starting && !radio.ConfiguredDisabled {
			continue // Accepted startup, including DFS checks. The UI reports this as pending.
		}
		if radio.Pending || radio.Enabled != (desired && !radio.ConfiguredDisabled) {
			return false
		}
	}
	return true
}

func (r *openWrt) radios(ctx context.Context, token string) ([]Radio, error) {
	data, err := r.call(ctx, token, "network.wireless", "status", map[string]any{})
	if err != nil {
		return nil, err
	}
	var devices map[string]struct {
		Up        *bool `json:"up"`
		Pending   bool  `json:"pending"`
		Autostart bool  `json:"autostart"`
		Disabled  bool  `json:"disabled"`
		Config    struct {
			Band string `json:"band"`
		} `json:"config"`
	}
	if err := json.Unmarshal(data, &devices); err != nil || len(devices) == 0 {
		return nil, errors.New("OpenWrt returned no wireless radios")
	}
	var radios []Radio
	for id, device := range devices {
		if device.Up == nil {
			return nil, errors.New("OpenWrt returned a radio without its current state")
		}
		band := map[string]string{"2g": "2.4GHz", "5g": "5GHz", "6g": "6GHz"}[device.Config.Band]
		if band == "" {
			band = id
		}
		radios = append(radios, Radio{ID: id, Band: band, Enabled: *device.Up, Pending: device.Pending,
			ConfiguredDisabled: device.Disabled, starting: device.Pending && device.Autostart})
	}
	slices.SortFunc(radios, func(a, b Radio) int { return strings.Compare(a.ID, b.ID) })
	return radios, nil
}
