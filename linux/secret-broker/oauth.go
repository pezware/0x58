package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// oauthSource trades a client id and secret for short-lived access tokens
// (RFC 6749 client credentials). The sealed secret never leaves this process;
// only access tokens go upstream, and only in the header this broker sets.
type oauthSource struct {
	id, secret string
	tokenURL   string
	client     *http.Client
	now        func() time.Time

	mu     sync.Mutex
	cached string
	expiry time.Time
}

// refreshMargin renews a token this long before it expires, so a request never
// leaves with a token that dies in flight.
const refreshMargin = time.Minute

func (s *oauthSource) token(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cached != "" && s.now().Add(refreshMargin).Before(s.expiry) {
		return s.cached, nil
	}

	form := url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {s.id},
		"client_secret": {s.secret},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := s.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("token request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("token endpoint answered %d", resp.StatusCode)
	}

	var body struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", fmt.Errorf("token response: %w", err)
	}
	if body.AccessToken == "" || body.ExpiresIn <= 0 {
		return "", fmt.Errorf("token response has no access_token or expires_in")
	}
	s.cached = body.AccessToken
	s.expiry = s.now().Add(time.Duration(body.ExpiresIn) * time.Second)
	return s.cached, nil
}
