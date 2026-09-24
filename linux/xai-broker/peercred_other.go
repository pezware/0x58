//go:build !linux

package main

import "net"

// SO_PEERCRED is Linux-only. Elsewhere the broker still works; the audit line
// just cannot name the caller. The devbox is Linux, so this only matters for
// running the tests on a Mac.
func peerCredentials(net.Conn) peer { return peer{} }
