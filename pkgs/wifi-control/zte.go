package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const wlanPath = "?_type=menuData&_tag=wlan_basiconoff_lua.lua"

var tokenPattern = regexp.MustCompile(`_sessionTmpToken\s*=\s*("(?:\\.|[^"\\])*")`)
var keyPattern = regexp.MustCompile(`var\s+pubKey\s*=\s*("(?:\\.|[^"\\])*")`)

type zteRouter struct {
	baseURL  string
	username string
	password string
	client   *http.Client
	gate     chan struct{}
}

func newZTERouter(baseURL, username, password, fingerprint string) (*zteRouter, error) {
	if err := validateRouterURL(baseURL, false); err != nil {
		return nil, err
	}
	client, err := routerHTTPClient(fingerprint)
	if err != nil {
		return nil, err
	}
	return &zteRouter{
		baseURL: strings.TrimRight(baseURL, "/") + "/", username: username, password: password,
		gate: make(chan struct{}, 1), client: client,
	}, nil
}

func (r *zteRouter) operate(ctx context.Context, desired *bool) (Result, error) {
	select {
	case r.gate <- struct{}{}:
		defer func() { <-r.gate }()
	case <-ctx.Done():
		return Result{}, ctx.Err()
	}
	jar, _ := cookiejar.New(nil)
	client := *r.client
	client.Jar = jar
	s := routerSession{router: r, client: &client}
	defer s.logout()
	if err := s.login(ctx); err != nil {
		return Result{}, err
	}
	radios, err := s.radios(ctx)
	if err != nil {
		return Result{}, err
	}
	result := Result{Radios: radios}
	if desired == nil || allEnabled(radios, *desired) {
		return result, nil
	}
	if err := s.set(ctx, radios, *desired); err != nil {
		return Result{}, err
	}
	for attempt := 0; attempt < 6; attempt++ {
		radios, err = s.radios(ctx)
		if err != nil {
			return Result{}, err
		}
		if allEnabled(radios, *desired) {
			return Result{Radios: radios, Changed: true}, nil
		}
		select {
		case <-time.After(time.Second):
		case <-ctx.Done():
			return Result{}, ctx.Err()
		}
	}
	return Result{}, errors.New("router did not confirm both requested radio states; refresh status before retrying")
}

func allEnabled(radios []Radio, enabled bool) bool {
	if len(radios) == 0 {
		return false
	}
	for _, radio := range radios {
		if radio.Pending || radio.Enabled != (enabled && !radio.ConfiguredDisabled) {
			return false
		}
	}
	return true
}

type routerSession struct {
	router *zteRouter
	client *http.Client
	token  string
	key    *rsa.PublicKey
}

func (s *routerSession) request(ctx context.Context, method, path, body, check string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, method, s.router.baseURL+path, strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Referer", s.router.baseURL)
	req.Header.Set("X-Requested-With", "XMLHttpRequest")
	if method == http.MethodPost {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
	}
	if check != "" {
		req.Header.Set("Check", check)
	}
	response, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("router request failed: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("router returned HTTP %d", response.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, 1<<20+1))
	if len(data) > 1<<20 {
		return nil, errors.New("router response exceeded size limit")
	}
	return data, err
}

func (s *routerSession) login(ctx context.Context) error {
	if _, err := s.request(ctx, http.MethodGet, "", "", ""); err != nil {
		return err
	}
	entry, err := s.request(ctx, http.MethodGet, "?_type=loginData&_tag=login_entry", "", "")
	if err != nil {
		return err
	}
	var login struct {
		Token   string          `json:"sess_token"`
		Locking json.RawMessage `json:"lockingTime"`
	}
	if err := json.Unmarshal(entry, &login); err != nil || login.Token == "" {
		return errors.New("invalid router login response")
	}
	locking := strings.Trim(string(login.Locking), `"`)
	if locking != "" && locking != "null" && locking != "0" {
		return errors.New("router login is temporarily locked")
	}
	data, err := s.request(ctx, http.MethodGet, "?_type=loginData&_tag=login_token", "", "")
	if err != nil {
		return err
	}
	var challenge strings.Builder
	decoder := xml.NewDecoder(strings.NewReader(string(data)))
	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return errors.New("invalid router login challenge")
		}
		if text, ok := token.(xml.CharData); ok {
			challenge.Write(text)
		}
	}
	if strings.TrimSpace(challenge.String()) == "" {
		return errors.New("empty router login challenge")
	}
	digest := sha256.Sum256([]byte(s.router.password + strings.TrimSpace(challenge.String())))
	body := url.Values{
		"Username": {s.router.username}, "Password": {hex.EncodeToString(digest[:])},
		"_sessionTOKEN": {login.Token}, "action": {"login"},
	}.Encode()
	data, err = s.request(ctx, http.MethodPost, "?_type=loginData&_tag=login_entry", body, "")
	if err != nil {
		return err
	}
	var result struct {
		Refresh bool   `json:"login_need_refresh"`
		Token   string `json:"sess_token"`
	}
	if err := json.Unmarshal(data, &result); err != nil || !result.Refresh {
		return errors.New("router authentication failed")
	}
	s.token = result.Token
	root, err := s.request(ctx, http.MethodGet, "", "", "")
	if err != nil {
		return err
	}
	if token, err := sessionToken(string(root)); err == nil {
		s.token = token
	}
	match := keyPattern.FindStringSubmatch(string(root))
	if len(match) != 2 {
		return errors.New("router request-check key was not found")
	}
	keyText, err := strconv.Unquote(match[1])
	if err != nil {
		return errors.New("invalid router public-key literal")
	}
	block, _ := pem.Decode([]byte(keyText))
	if block == nil {
		return errors.New("invalid router public key")
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return errors.New("invalid router public key")
	}
	var ok bool
	s.key, ok = key.(*rsa.PublicKey)
	if !ok {
		return errors.New("router public key is not RSA")
	}
	page, err := s.request(ctx, http.MethodGet, "?_type=menuView&_tag=wlanBasic", "", "")
	if err != nil {
		return err
	}
	s.token, err = sessionToken(string(page))
	return err
}

func sessionToken(source string) (string, error) {
	matches := tokenPattern.FindAllStringSubmatch(source, -1)
	for index := len(matches) - 1; index >= 0; index-- {
		// Go's quoted-string decoder also understands the firmware's JavaScript \xNN escapes.
		token, err := strconv.Unquote(matches[index][1])
		if err == nil && token != "" {
			return token, nil
		}
	}
	return "", errors.New("router session token was not found")
}

type wlanResponse struct {
	Error string `xml:"IF_ERRORSTR"`
	Items []struct {
		Names  []string `xml:"ParaName"`
		Values []string `xml:"ParaValue"`
	} `xml:"OBJ_WLANSETTING_ID>Instance"`
}

func parseWLAN(data []byte) (wlanResponse, error) {
	var response wlanResponse
	if err := xml.Unmarshal(data, &response); err != nil {
		return response, errors.New("invalid router WLAN response")
	}
	if response.Error != "SUCC" {
		return response, errors.New("router rejected the WLAN request")
	}
	return response, nil
}

func (s *routerSession) radios(ctx context.Context) ([]Radio, error) {
	data, err := s.request(ctx, http.MethodGet, wlanPath, "", "")
	if err != nil {
		return nil, err
	}
	response, err := parseWLAN(data)
	if err != nil {
		return nil, err
	}
	var radios []Radio
	seen := make(map[string]bool)
	for _, item := range response.Items {
		if len(item.Names) != len(item.Values) {
			return nil, errors.New("invalid router radio fields")
		}
		fields := make(map[string]string)
		for index, name := range item.Names {
			fields[name] = item.Values[index]
		}
		id, band, state := fields["_InstID"], fields["Band"], fields["RadioStatus"]
		if seen[id] || !((id == "DEV.WIFI.RD1" && band == "2.4GHz") || (id == "DEV.WIFI.RD2" && band == "5GHz")) || (state != "0" && state != "1") {
			return nil, errors.New("unexpected router radio configuration")
		}
		seen[id] = true
		radios = append(radios, Radio{ID: id, Band: band, Enabled: state == "1"})
	}
	if len(radios) != 2 {
		return nil, errors.New("expected both 2.4 GHz and 5 GHz radio states")
	}
	return radios, nil
}

func (s *routerSession) set(ctx context.Context, radios []Radio, enabled bool) error {
	state := "0"
	if enabled {
		state = "1"
	}
	fields := url.Values{
		"IF_ACTION": {"Apply"}, "RadioStatus": {""}, "_InstID": {""}, "Band": {""},
		"Btn_cancel_WlanBasicAdConf": {""}, "Btn_apply_WlanBasicAdConf": {""}, "_sessionTOKEN": {s.token},
	}
	for index, radio := range radios {
		suffix := "_" + strconv.Itoa(index)
		fields.Set("_InstID"+suffix, radio.ID)
		fields.Set("Band"+suffix, radio.Band)
		fields.Set("RadioStatus"+suffix, state)
	}
	body := fields.Encode()
	digest := sha256.Sum256([]byte(body))
	check, err := rsa.EncryptPKCS1v15(rand.Reader, s.key, []byte(hex.EncodeToString(digest[:])))
	if err != nil {
		return errors.New("could not generate router request check")
	}
	data, err := s.request(ctx, http.MethodPost, wlanPath, body, base64.StdEncoding.EncodeToString(check))
	if err != nil {
		return err
	}
	_, err = parseWLAN(data)
	return err
}

func (s *routerSession) logout() {
	if s.token == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, _ = s.request(ctx, http.MethodPost, "?_type=loginData&_tag=logout_entry",
		url.Values{"IF_LogOff": {"1"}, "_sessionTOKEN": {s.token}}.Encode(), "")
}
