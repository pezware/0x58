package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

// upstream records the Authorization header it received and answers 200.
func upstream(t *testing.T) (*httptest.Server, *string) {
	t.Helper()
	var seen string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = r.Header.Get("Authorization")
		_, _ = io.WriteString(w, "upstream ok")
	}))
	t.Cleanup(srv.Close)
	return srv, &seen
}

func handlerFor(t *testing.T, target string, rpm int) http.Handler {
	t.Helper()
	u, err := url.Parse(target)
	if err != nil {
		t.Fatal(err)
	}
	return newHandler("xai-secret", u, rpm)
}

func TestReplacesClientAuthorization(t *testing.T) {
	up, seen := upstream(t)
	h := handlerFor(t, up.URL, 10)

	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader("{}"))
	req.Header.Set("Authorization", "Bearer placeholder-from-sdk")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if *seen != "Bearer xai-secret" {
		t.Fatalf("upstream saw Authorization %q, want the broker's key", *seen)
	}
}

func TestHealthzNeedsNoUpstream(t *testing.T) {
	h := handlerFor(t, "http://127.0.0.1:1", 10) // nothing listens there

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("healthz returned %d, want 200", rec.Code)
	}
}

func TestPathsOutsideV1AreNotProxied(t *testing.T) {
	up, seen := upstream(t)
	h := handlerFor(t, up.URL, 10)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/admin", nil))

	if *seen != "" {
		t.Fatalf("upstream was called for /admin; the broker must only forward /v1/")
	}
}

func TestBudgetRefusesBeyondLimit(t *testing.T) {
	up, _ := upstream(t)
	h := handlerFor(t, up.URL, 2)

	var last int
	for i := 0; i < 3; i++ {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/models", nil))
		last = rec.Code
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

func TestLoadKeyRefusesNonXAIKey(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(dir+"/cred", []byte("sk-not-xai"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("CREDENTIALS_DIRECTORY", dir)

	if _, err := loadKey("cred"); err == nil {
		t.Fatal("loadKey accepted a key without the xai- prefix")
	}
}

func TestLoadKeyFailsWithoutAnySource(t *testing.T) {
	t.Setenv("CREDENTIALS_DIRECTORY", "")

	// No keychain item has this name, and off macOS there is no keychain.
	if _, err := loadKey("xai-broker-test-no-such-item"); err == nil {
		t.Fatal("loadKey found a key where none exists")
	}
}
