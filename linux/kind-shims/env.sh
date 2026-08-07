# Source me before driving kind on this box:
#
#     . ~/.local/share/kind-shims/env.sh
#
# WHY A SOURCEABLE FILE RATHER THAN A PROFILE SNIPPET
#
# Agent sessions and `ssh host cmd` both run non-login, non-interactive shells,
# which read neither ~/.profile nor the interactive half of ~/.bashrc. Anything
# that has to be true for `task -d dev/kind ...` must be sourced explicitly by
# whatever runs it, so it lives in a file with one job instead of a login path
# that will not fire.
#
# This is the file three sessions reconstructed by hand in $TMPDIR. The reboot
# took the last copy with it.

_kind_shims="$HOME/.local/share/kind-shims"

# Shims FIRST, so `docker` and `podman` resolve here rather than to a distro
# binary. ~/.local/bin must still precede the mise shims, so the gh wrapper
# installed there keeps winning over mise's.
case ":${PATH}:" in
    *":${_kind_shims}:"*) ;;
    *) PATH="${_kind_shims}:${HOME}/.local/bin:${HOME}/.local/share/mise/shims:${PATH}" ;;
esac
export PATH

# kind only talks to podman when told to; without this it looks for docker and
# reports it as missing even with the shim in place.
export KIND_EXPERIMENTAL_PROVIDER=podman

# podman needs a WRITABLE runtime dir. The default /run/user/<uid> is mounted
# read-only inside the Claude Code sandbox and fails with
#   set sticky bit on: chmod /run/user/<uid>/libpod: read-only file system
# which reads as a privilege wall and is not one. That misdiagnosis is the
# expensive part -- the fix is a writable directory, not more privilege.
#
# The podman SOCKET is unaffected and still lives under the real runtime dir;
# the shims hardcode that rather than deriving it from this variable.
export XDG_RUNTIME_DIR="${HOME}/.cache/podman-run"
mkdir -p "${XDG_RUNTIME_DIR}" 2>/dev/null || true
chmod 700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true

# kind stages `docker save` archives in TMPDIR. When /tmp was a RAM-backed
# tmpfs this ENOSPC'd at image 10 of 10; /tmp is on disk now, so the default is
# correct -- named here so the next person does not have to rediscover why it
# matters.
export TMPDIR="${TMPDIR:-/tmp}"

unset _kind_shims
