//go:build darwin

package main

import (
	"fmt"
	"os/exec"
	"strings"
)

// keychainKey reads the key from the login keychain. A Mac has no systemd
// credentials, and the keychain keeps the key out of files and env vars.
func keychainKey(name string) (string, error) {
	out, err := exec.Command("/usr/bin/security", "find-generic-password", "-s", name, "-w").Output()
	if err != nil {
		return "", fmt.Errorf("keychain item %q: %w", name, err)
	}
	return strings.TrimSpace(string(out)), nil
}
