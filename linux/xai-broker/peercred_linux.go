package main

import (
	"net"
	"syscall"
)

// peerCredentials asks the kernel which process is on the other end of the
// unix socket. The audit line depends on it; it is the difference between
// "someone called the broker" and "uid 1000, pid N called the broker".
func peerCredentials(c net.Conn) peer {
	uc, ok := c.(*net.UnixConn)
	if !ok {
		return peer{}
	}
	raw, err := uc.SyscallConn()
	if err != nil {
		return peer{}
	}
	var cred *syscall.Ucred
	_ = raw.Control(func(fd uintptr) {
		cred, _ = syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
	})
	if cred == nil {
		return peer{}
	}
	return peer{uid: cred.Uid, pid: cred.Pid}
}
