// secret-broker hands a sandboxed agent an API endpoint without handing it the key.
//
// It listens on a unix socket, accepts requests under one path prefix, replaces
// whatever credential header the client sent with the real one, and forwards to
// one upstream. The credential is read once at start from the systemd credentials
// directory, so it exists in this process and in a root-sealed file, and nowhere
// the agent's uid can read.
//
// One process serves one route. secret-broker@<route>.service runs an instance per
// key, configured by /etc/secret-broker/<route>.env, so adding a key adds a file,
// not code. See linux/secret-broker/README.md.
//
// Why a unix socket: the Claude Code sandbox on the devbox gives each session a
// network namespace with loopback only. Host TCP on 127.0.0.1 is unreachable from
// inside it; a unix socket on a bind-mounted path is reachable, which is how the
// rootless podman socket already works in-session.
//
// What this does not do: it cannot stop a caller from spending on the key. That
// is the same shape as a signing oracle, and the backstop is the per-key scope on
// the provider side plus the request budget below.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// config is one route: where callers connect, what the broker forwards to, and
// how it proves who it is.
type config struct {
	socket       string
	upstream     *url.URL
	credential   string
	path         string // a ServeMux pattern: "/v1/" is a subtree, "/a/b" one path
	header       string
	headerPrefix string
	keyPrefix    string
	auth         string // "static" or "oauth2"
	tokenURL     string
	rpm          int
}

func main() {
	log.SetFlags(0)

	cfg, err := loadConfig(os.LookupEnv)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	raw, err := loadKey(cfg.credential)
	if err != nil {
		log.Fatalf("load key: %v", err)
	}
	src, err := newSource(cfg, raw, upstreamTransport())
	if err != nil {
		log.Fatalf("credential %q: %v", cfg.credential, err)
	}

	handler := newHandler(cfg, src)

	// A stale socket from an unclean exit blocks bind().
	if err := os.Remove(cfg.socket); err != nil && !errors.Is(err, os.ErrNotExist) {
		log.Fatalf("remove stale socket: %v", err)
	}
	ln, err := net.Listen("unix", cfg.socket)
	if err != nil {
		log.Fatalf("listen %s: %v", cfg.socket, err)
	}
	// connect(2) on a unix socket needs write permission on the socket file.
	// The directory is 0755 root-owned (RuntimeDirectory), so nobody but root
	// can unlink or replace it; 0666 on the file only lets callers connect.
	if err := os.Chmod(cfg.socket, 0o666); err != nil {
		log.Fatalf("chmod socket: %v", err)
	}

	srv := &http.Server{
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		ConnContext:       withPeer,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	log.Printf("secret-broker listening on %s: %s -> %s (%s auth, budget %d req/min)",
		cfg.socket, cfg.path, cfg.upstream, cfg.auth, cfg.rpm)
	if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve: %v", err)
	}
}

// loadConfig reads the BROKER_* variables. It takes a lookup function so the
// tests can hand it a map instead of mutating the process environment.
func loadConfig(lookup func(string) (string, bool)) (config, error) {
	get := func(name, def string) string {
		if v, ok := lookup(name); ok && v != "" {
			return v
		}
		return def
	}
	cfg := config{
		socket:     get("BROKER_SOCKET", ""),
		credential: get("BROKER_CREDENTIAL", ""),
		path:       get("BROKER_PATH", ""),
		header:     get("BROKER_HEADER", "Authorization"),
		keyPrefix:  get("BROKER_KEY_PREFIX", ""),
		auth:       get("BROKER_AUTH", "static"),
		tokenURL:   get("BROKER_TOKEN_URL", ""),
	}
	// Set-but-empty is meaningful here: an x-api-key header carries the bare key.
	cfg.headerPrefix = "Bearer "
	if v, ok := lookup("BROKER_HEADER_PREFIX"); ok {
		cfg.headerPrefix = v
	}

	for name, v := range map[string]string{
		"BROKER_SOCKET": cfg.socket, "BROKER_CREDENTIAL": cfg.credential, "BROKER_PATH": cfg.path,
	} {
		if v == "" {
			return config{}, fmt.Errorf("%s is required", name)
		}
	}
	if !strings.HasPrefix(cfg.path, "/") {
		return config{}, fmt.Errorf("BROKER_PATH %q must start with /", cfg.path)
	}
	up, err := url.Parse(get("BROKER_UPSTREAM", ""))
	if err != nil || up.Scheme != "https" || up.Host == "" {
		return config{}, errors.New("BROKER_UPSTREAM must be an https:// URL")
	}
	cfg.upstream = up

	switch cfg.auth {
	case "static":
	case "oauth2":
		if !strings.HasPrefix(cfg.tokenURL, "https://") {
			return config{}, errors.New("BROKER_AUTH=oauth2 needs an https:// BROKER_TOKEN_URL")
		}
	default:
		return config{}, fmt.Errorf("BROKER_AUTH %q: want static or oauth2", cfg.auth)
	}

	cfg.rpm, err = strconv.Atoi(get("BROKER_RPM", "60"))
	if err != nil || cfg.rpm < 1 {
		return config{}, errors.New("BROKER_RPM must be a positive integer")
	}
	return cfg, nil
}

// loadKey reads the credential systemd placed in $CREDENTIALS_DIRECTORY. That
// directory is a private tmpfs for this unit, decrypted by PID 1 from the
// root-owned ciphertext in /etc/credstore.encrypted. Without systemd, on a Mac,
// it reads the login keychain item of the same name instead.
func loadKey(name string) (string, error) {
	if dir := os.Getenv("CREDENTIALS_DIRECTORY"); dir != "" {
		raw, err := os.ReadFile(dir + "/" + name)
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(string(raw)), nil
	}
	return keychainKey(name)
}

// tokenSource yields the value that goes after the header prefix.
type tokenSource interface {
	token(context.Context) (string, error)
}

type staticSource string

func (s staticSource) token(context.Context) (string, error) { return string(s), nil }

// newSource checks the raw credential against the route and wraps it. A typo in
// a sealed credential then fails at start, not on the first real request.
func newSource(cfg config, raw string, rt http.RoundTripper) (tokenSource, error) {
	secret := raw
	var id string
	if cfg.auth == "oauth2" {
		var ok bool
		if id, secret, ok = strings.Cut(raw, ":"); !ok || id == "" || secret == "" {
			return nil, errors.New("an oauth2 credential is client_id:client_secret")
		}
	}
	if !strings.HasPrefix(secret, cfg.keyPrefix) {
		return nil, fmt.Errorf("secret does not start with %q", cfg.keyPrefix)
	}
	if cfg.auth == "oauth2" {
		return &oauthSource{
			id: id, secret: secret, tokenURL: cfg.tokenURL,
			client: &http.Client{Transport: rt, Timeout: 30 * time.Second},
			now:    time.Now,
		}, nil
	}
	return staticSource(secret), nil
}

type tokenKey struct{}

// newHandler is the whole request path, split from main so the tests can drive
// it against an httptest upstream.
func newHandler(cfg config, src tokenSource) http.Handler {
	target := cfg.upstream
	proxy := &httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.SetURL(target)
			pr.Out.Host = target.Host
			// SDKs insist on sending some key. Whatever it was, it was not this one.
			pr.Out.Header.Del("Authorization")
			pr.Out.Header.Del("X-Api-Key")
			pr.Out.Header.Del(cfg.header)
			tok, _ := pr.In.Context().Value(tokenKey{}).(string)
			pr.Out.Header.Set(cfg.header, cfg.headerPrefix+tok)
		},
		// -1 flushes every write, which is what server-sent event streams need.
		FlushInterval: -1,
		Transport:     upstreamTransport(),
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			log.Printf("upstream error: %s %s: %v", r.Method, r.URL.Path, err)
			http.Error(w, "upstream unavailable", http.StatusBadGateway)
		},
	}

	budget := newBudget(cfg.rpm)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok\n"))
	})
	mux.HandleFunc(cfg.path, func(w http.ResponseWriter, r *http.Request) {
		if !budget.allow(time.Now()) {
			http.Error(w, "request budget exhausted, retry next minute", http.StatusTooManyRequests)
			return
		}
		tok, err := src.token(r.Context())
		if err != nil {
			log.Printf("credential: %v", err)
			http.Error(w, "broker cannot authenticate upstream", http.StatusBadGateway)
			return
		}
		proxy.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), tokenKey{}, tok)))
	})
	return logRequests(mux)
}

func upstreamTransport() http.RoundTripper {
	return &http.Transport{
		Proxy:                 nil, // the host has direct egress; never trust an env proxy with the key
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 2 * time.Minute,
		IdleConnTimeout:       90 * time.Second,
	}
}

// budget is a fixed one-minute window. Coarse on purpose: this is a guard
// against a runaway loop, not a fair scheduler.
type budget struct {
	mu     sync.Mutex
	limit  int
	window time.Time
	count  int
}

func newBudget(limit int) *budget { return &budget{limit: limit} }

func (b *budget) allow(now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if now.Sub(b.window) >= time.Minute {
		b.window = now
		b.count = 0
	}
	if b.count >= b.limit {
		return false
	}
	b.count++
	return true
}

// logRequests writes one line per request: who (uid/pid from SO_PEERCRED),
// what, and the outcome. Never headers, never bodies.
func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &recorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		p := peerFrom(r.Context())
		log.Printf("uid=%d pid=%d %s %s -> %d %dB %s",
			p.uid, p.pid, r.Method, r.URL.Path, rec.status, rec.bytes,
			time.Since(start).Round(time.Millisecond))
	})
}

type recorder struct {
	http.ResponseWriter
	status int
	bytes  int64
}

func (r *recorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *recorder) Write(b []byte) (int, error) {
	n, err := r.ResponseWriter.Write(b)
	r.bytes += int64(n)
	return n, err
}

// Unwrap lets http.ResponseController reach the underlying Flusher, which the
// reverse proxy needs for streaming responses.
func (r *recorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

// peer identifies the connecting process. Zero values mean "not a unix socket"
// or "platform cannot tell", which the log line shows as uid=0 pid=0.
type peer struct {
	uid uint32
	pid int32
}

type peerKey struct{}

func withPeer(ctx context.Context, c net.Conn) context.Context {
	return context.WithValue(ctx, peerKey{}, peerCredentials(c))
}

func peerFrom(ctx context.Context) peer {
	p, _ := ctx.Value(peerKey{}).(peer)
	return p
}
