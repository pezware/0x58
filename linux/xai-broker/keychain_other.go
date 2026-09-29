//go:build !darwin

package main

import "errors"

// keychainKey exists on macOS only. Elsewhere the key must come from systemd.
func keychainKey(string) (string, error) {
	return "", errors.New("CREDENTIALS_DIRECTORY is unset: run under systemd with LoadCredentialEncrypted")
}
