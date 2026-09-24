// xai-broker hands a sandboxed agent an xAI endpoint without handing it the key.
//
// It listens on a unix socket, accepts requests for /v1/*, replaces whatever
// Authorization header the client sent with the real bearer token, and forwards
// to api.x.ai. The key is read once at start from the systemd credentials
// directory, so it exists in this process and in a root-sealed file, and nowhere
// the agent's uid can read.
//
// Why a unix socket: the Claude Code sandbox on the devbox gives each session a
// network namespace with loopback only. Host TCP on 127.0.0.1 is unreachable from
// inside it; a unix socket on a bind-mounted path is reachable, which is how the
// rootless podman socket already works in-session.
//
// What this does not do: it cannot stop a caller from spending on the key. That
// is the same shape as a signing oracle, and the backstop is the per-key spend
// limit on the xAI side plus the request budget below.
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

func main() {
	log.SetFlags(0)

	socket := envOr("XAI_BROKER_SOCKET", "/run/xai-broker/xai.sock")
	upstream := envOr("XAI_BROKER_UPSTREAM", "https://api.x.ai")
	credential := envOr("XAI_BROKER_CREDENTIAL", "xai-smallscreen")
	rpm, err := strconv.Atoi(envOr("XAI_BROKER_RPM", "60"))
	if err != nil || rpm < 1 {
		log.Fatalf("XAI_BROKER_RPM must be a positive integer")
	}

	key, err := loadKey(credential)
	if err != nil {
		log.Fatalf("load key: %v", err)
	}
	target, err := url.Parse(upstream)
	if err != nil {
		log.Fatalf("XAI_BROKER_UPSTREAM: %v", err)
	}

	handler := newHandler(key, target, rpm)

	// A stale socket from an unclean exit blocks bind().
	if err := os.Remove(socket); err != nil && !errors.Is(err, os.ErrNotExist) {
		log.Fatalf("remove stale socket: %v", err)
	}
	ln, err := net.Listen("unix", socket)
	if err != nil {
		log.Fatalf("listen %s: %v", socket, err)
	}
	// connect(2) on a unix socket needs write permission on the socket file.
	// The directory is 0755 root-owned (RuntimeDirectory), so nobody but root
	// can unlink or replace it; 0666 on the file only lets callers connect.
	if err := os.Chmod(socket, 0o666); err != nil {
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

	log.Printf("xai-broker listening on %s -> %s (budget %d req/min)", socket, upstream, rpm)
	if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve: %v", err)
	}
}

// loadKey reads the credential systemd placed in $CREDENTIALS_DIRECTORY. That
// directory is a private tmpfs for this unit, decrypted by PID 1 from the
// root-owned ciphertext in /etc/credstore.encrypted.
func loadKey(name string) (string, error) {
	dir := os.Getenv("CREDENTIALS_DIRECTORY")
	if dir == "" {
		return "", errors.New("CREDENTIALS_DIRECTORY is unset: run under systemd with LoadCredentialEncrypted")
	}
	raw, err := os.ReadFile(dir + "/" + name)
	if err != nil {
		return "", err
	}
	key := strings.TrimSpace(string(raw))
	if !strings.HasPrefix(key, "xai-") {
		return "", fmt.Errorf("credential %q does not look like an xAI key", name)
	}
	return key, nil
}

// newHandler is the whole request path, split from main so the tests can drive
// it against an httptest upstream.
func newHandler(key string, target *url.URL, rpm int) http.Handler {
	proxy := &httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.SetURL(target)
			pr.Out.Host = target.Host
			// SDKs insist on sending some key. Whatever it was, it was not this one.
			pr.Out.Header.Del("Authorization")
			pr.Out.Header.Del("X-Api-Key")
			pr.Out.Header.Set("Authorization", "Bearer "+key)
		},
		// -1 flushes every write, which is what server-sent event streams need.
		FlushInterval: -1,
		Transport: &http.Transport{
			Proxy:                 nil, // the host has direct egress; never trust an env proxy for the key
			TLSHandshakeTimeout:   10 * time.Second,
			ResponseHeaderTimeout: 2 * time.Minute,
			IdleConnTimeout:       90 * time.Second,
		},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			log.Printf("upstream error: %s %s: %v", r.Method, r.URL.Path, err)
			http.Error(w, "upstream unavailable", http.StatusBadGateway)
		},
	}

	budget := newBudget(rpm)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok\n"))
	})
	mux.HandleFunc("/v1/", func(w http.ResponseWriter, r *http.Request) {
		if !budget.allow(time.Now()) {
			http.Error(w, "request budget exhausted, retry next minute", http.StatusTooManyRequests)
			return
		}
		proxy.ServeHTTP(w, r)
	})
	return logRequests(mux)
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

func envOr(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}
