package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

// upstream records the request headers it received and answers 200.
func upstream(t *testing.T) (*httptest.Server, *http.Header) {
	t.Helper()
	seen := http.Header{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = r.Header.Clone()
		_, _ = io.WriteString(w, "upstream ok")
	}))
	t.Cleanup(srv.Close)
	return srv, &seen
}

// route is a static-auth config aimed at target, the shape of the xai route.
func route(t *testing.T, target string, rpm int) config {
	t.Helper()
	u, err := url.Parse(target)
	if err != nil {
		t.Fatal(err)
	}
	return config{upstream: u, path: "/v1/", header: "Authorization", headerPrefix: "Bearer ", auth: "static", rpm: rpm}
}

func serve(h http.Handler, method, path string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, strings.NewReader("{}")))
	return rec
}

func TestReplacesClientAuthorization(t *testing.T) {
	up, seen := upstream(t)
	h := newHandler(route(t, up.URL, 10), staticSource("xai-secret"))

	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader("{}"))
	req.Header.Set("Authorization", "Bearer placeholder-from-sdk")
	h.ServeHTTP(httptest.NewRecorder(), req)

	if got := seen.Get("Authorization"); got != "Bearer xai-secret" {
		t.Fatalf("upstream saw Authorization %q, want the broker's key", got)
	}
}

func TestCustomHeaderCarriesBareKey(t *testing.T) {
	up, seen := upstream(t)
	cfg := route(t, up.URL, 10)
	cfg.header, cfg.headerPrefix = "X-Api-Key", ""
	h := newHandler(cfg, staticSource("sk-secret"))

	req := httptest.NewRequest(http.MethodPost, "/v1/messages", nil)
	req.Header.Set("Authorization", "Bearer placeholder")
	h.ServeHTTP(httptest.NewRecorder(), req)

	if got := seen.Get("X-Api-Key") + "|" + seen.Get("Authorization"); got != "sk-secret|" {
		t.Fatalf("upstream saw X-Api-Key|Authorization = %q, want the bare key and no Authorization", got)
	}
}

func TestHealthzNeedsNoUpstream(t *testing.T) {
	h := newHandler(route(t, "http://127.0.0.1:1", 10), staticSource("k")) // nothing listens there

	if rec := serve(h, http.MethodGet, "/healthz"); rec.Code != http.StatusOK {
		t.Fatalf("healthz returned %d, want 200", rec.Code)
	}
}

func TestPathsOutsideTheRouteAreNotProxied(t *testing.T) {
	up, seen := upstream(t)
	h := newHandler(route(t, up.URL, 10), staticSource("k"))

	serve(h, http.MethodGet, "/admin")

	if len(*seen) != 0 {
		t.Fatal("upstream was called for /admin; the broker must only forward /v1/")
	}
}

func TestExactPathRouteRefusesSubpaths(t *testing.T) {
	up, seen := upstream(t)
	cfg := route(t, up.URL, 10)
	cfg.path = "/api/v2/tailnet/-/keys"
	h := newHandler(cfg, staticSource("k"))

	serve(h, http.MethodDelete, "/api/v2/tailnet/-/keys/k123")

	if len(*seen) != 0 {
		t.Fatal("upstream was called for a subpath of an exact route")
	}
}

func TestBudgetRefusesBeyondLimit(t *testing.T) {
	up, _ := upstream(t)
	h := newHandler(route(t, up.URL, 2), staticSource("k"))

	var last int
	for i := 0; i < 3; i++ {
		last = serve(h, http.MethodGet, "/v1/models").Code
	}

	if last != http.StatusTooManyRequests {
		t.Fatalf("third request in one minute returned %d, want 429", last)
	}
}

func TestBudgetResetsAfterAMinute(t *testing.T) {
	b := newBudget(1)
	start := time.Unix(1_700_000_000, 0)
	b.allow(start)

	if !b.allow(start.Add(time.Minute)) {
		t.Fatal("budget did not reset after one minute")
	}
}

// env is a lookup over a map, with a valid static route as the base.
func env(over map[string]string) func(string) (string, bool) {
	m := map[string]string{
		"BROKER_SOCKET":     "/run/x-broker/x.sock",
		"BROKER_CREDENTIAL": "x",
		"BROKER_PATH":       "/v1/",
		"BROKER_UPSTREAM":   "https://api.example.com",
	}
	for k, v := range over {
		m[k] = v
	}
	return func(k string) (string, bool) { v, ok := m[k]; return v, ok }
}

func TestConfigRequiresPath(t *testing.T) {
	if _, err := loadConfig(env(map[string]string{"BROKER_PATH": ""})); err == nil {
		t.Fatal("loadConfig accepted a route with no path")
	}
}

func TestConfigRefusesPlainHTTPUpstream(t *testing.T) {
	if _, err := loadConfig(env(map[string]string{"BROKER_UPSTREAM": "http://api.example.com"})); err == nil {
		t.Fatal("loadConfig accepted an upstream that would send the key in clear text")
	}
}

func TestConfigOAuthNeedsTokenURL(t *testing.T) {
	if _, err := loadConfig(env(map[string]string{"BROKER_AUTH": "oauth2"})); err == nil {
		t.Fatal("loadConfig accepted oauth2 with no token URL")
	}
}

func TestConfigKeepsEmptyHeaderPrefix(t *testing.T) {
	cfg, err := loadConfig(env(map[string]string{"BROKER_HEADER_PREFIX": ""}))
	if err != nil || cfg.headerPrefix != "" {
		t.Fatalf("headerPrefix = %q, %v; want empty, as set", cfg.headerPrefix, err)
	}
}

func TestConfigDefaultsToBearer(t *testing.T) {
	cfg, err := loadConfig(env(nil))
	if err != nil || cfg.headerPrefix != "Bearer " {
		t.Fatalf("headerPrefix = %q, %v; want \"Bearer \"", cfg.headerPrefix, err)
	}
}

func TestSourceRefusesWrongKeyPrefix(t *testing.T) {
	cfg := config{auth: "static", keyPrefix: "xai-"}
	if _, err := newSource(cfg, "sk-not-xai", nil); err == nil {
		t.Fatal("newSource accepted a key without the route's prefix")
	}
}

func TestSourceRefusesMalformedOAuthCredential(t *testing.T) {
	cfg := config{auth: "oauth2", tokenURL: "https://example.com/token"}
	if _, err := newSource(cfg, "no-colon-here", nil); err == nil {
		t.Fatal("newSource accepted an oauth2 credential without client_id:")
	}
}

// tokenServer issues "tok-N" for the Nth request, valid for ttl seconds.
func tokenServer(t *testing.T, ttl int, status int) (*httptest.Server, *int) {
	t.Helper()
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.FormValue("client_id") != "cid" || r.FormValue("client_secret") != "tskey-client-s" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		w.WriteHeader(status)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"access_token": "tok-" + string(rune('0'+calls)), "expires_in": ttl,
		})
	}))
	t.Cleanup(srv.Close)
	return srv, &calls
}

func oauthFor(t *testing.T, tokenURL string, now *time.Time) *oauthSource {
	t.Helper()
	cfg := config{auth: "oauth2", tokenURL: tokenURL, keyPrefix: "tskey-client-"}
	src, err := newSource(cfg, "cid:tskey-client-s", http.DefaultTransport)
	if err != nil {
		t.Fatal(err)
	}
	o := src.(*oauthSource)
	o.now = func() time.Time { return *now }
	return o
}

func TestOAuthCachesTokenUntilNearExpiry(t *testing.T) {
	srv, calls := tokenServer(t, 3600, http.StatusOK)
	now := time.Unix(1_700_000_000, 0)
	o := oauthFor(t, srv.URL, &now)

	_, _ = o.token(context.Background())
	now = now.Add(58 * time.Minute)
	_, _ = o.token(context.Background())

	if *calls != 1 {
		t.Fatalf("token endpoint called %d times within the token's life, want 1", *calls)
	}
}

func TestOAuthRefreshesInsideTheMargin(t *testing.T) {
	srv, calls := tokenServer(t, 3600, http.StatusOK)
	now := time.Unix(1_700_000_000, 0)
	o := oauthFor(t, srv.URL, &now)

	_, _ = o.token(context.Background())
	now = now.Add(59*time.Minute + 30*time.Second)
	_, _ = o.token(context.Background())

	if *calls != 2 {
		t.Fatalf("token endpoint called %d times, want a refresh 30s before expiry", *calls)
	}
}

func TestOAuthTokenReachesUpstream(t *testing.T) {
	tokens, _ := tokenServer(t, 3600, http.StatusOK)
	up, seen := upstream(t)
	now := time.Unix(1_700_000_000, 0)
	h := newHandler(route(t, up.URL, 10), oauthFor(t, tokens.URL, &now))

	serve(h, http.MethodPost, "/v1/keys")

	if got := seen.Get("Authorization"); got != "Bearer tok-1" {
		t.Fatalf("upstream saw Authorization %q, want the access token, never the client secret", got)
	}
}

func TestOAuthFailureAnswers502(t *testing.T) {
	tokens, _ := tokenServer(t, 3600, http.StatusInternalServerError)
	up, _ := upstream(t)
	now := time.Unix(1_700_000_000, 0)
	h := newHandler(route(t, up.URL, 10), oauthFor(t, tokens.URL, &now))

	if rec := serve(h, http.MethodPost, "/v1/keys"); rec.Code != http.StatusBadGateway {
		t.Fatalf("request with a failed token exchange returned %d, want 502", rec.Code)
	}
}

func TestLoadKeyReadsCredentialsDirectory(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(dir+"/cred", []byte("xai-from-systemd\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("CREDENTIALS_DIRECTORY", dir)

	if key, err := loadKey("cred"); err != nil || key != "xai-from-systemd" {
		t.Fatalf("loadKey = %q, %v; want xai-from-systemd", key, err)
	}
}

func TestLoadKeyFailsWithoutAnySource(t *testing.T) {
	t.Setenv("CREDENTIALS_DIRECTORY", "")

	// No keychain item has this name, and off macOS there is no keychain.
	if _, err := loadKey("secret-broker-test-no-such-item"); err == nil {
		t.Fatal("loadKey found a key where none exists")
	}
}
