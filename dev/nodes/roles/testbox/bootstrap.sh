#!/usr/bin/env bash
# testbox role — the shared, SINGLETON build-and-test box.
#
# One exists at a time. Agents on the devbox claim it, use it, and either hand
# it to the next agent in the queue or destroy it. `testbox status` says who
# holds it and what it has cost so far.
#
# It holds nothing worth keeping. The repo, the GitHub tokens and the agent
# sessions all stay on the devbox; this node receives a working tree over rsync,
# compiles it, runs the stack against it, and is destroyed when the queue is
# empty. Carrying no credentials is what makes it safe to throw away, and it is
# a property to preserve rather than a limitation to route around: this box
# cannot reach GitHub, and it must not be given a way to.
#
# Why not the k8s role with a bigger plan: that role installs docker and kind
# and stops, because a kind host needs nothing else. Builds here need a JDK, a
# compose provider and rsync as well — and this box does both jobs, which is the
# entire point. Build and test on separate machines cost a staged-tar disk
# crisis, a void e2e run, and an accidental image deletion on 2026-09-03.
set -euo pipefail

# shellcheck source=/dev/null
. /usr/local/sbin/node-common.sh
common_main

USER_NAME=arbeitandy
USER_HOME="/home/$USER_NAME"

as_user() { sudo -u "$USER_NAME" -H bash -lc "$*"; }

# ── PATH for NON-INTERACTIVE ssh, which is the only way this box is used ─────
# The handoff is `ssh testbox 'cd repo && ./gradlew build'`. That runs a
# non-interactive bash, and Debian's stock ~/.bashrc returns on line 6 when the
# shell is not interactive -- so anything exported below that line is invisible
# to every command any agent will ever run. A toolchain that works when
# you log in and vanishes when an agent calls it is the failure this avoids.
#
# Two mechanisms, because they cover different shells: profile.d serves login
# shells, and the prepended block serves `ssh host 'cmd'`. Tailscale SSH does
# not reliably run PAM, so /etc/environment is not a third option.
install_build_env() {
    cat > /etc/profile.d/0x58-build-env.sh <<'ENV'
# 0x58 testbox — mise shims plus JAVA_HOME.
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
[ -x "$HOME/.local/bin/mise" ] && export JAVA_HOME="$($HOME/.local/bin/mise where java 2>/dev/null)"
ENV
    chmod 644 /etc/profile.d/0x58-build-env.sh

    local rc="$USER_HOME/.bashrc"
    grep -q '0x58-build-env' "$rc" 2>/dev/null && return 0
    local tmp; tmp=$(mktemp)
    {
        echo '# 0x58-build-env — ABOVE the interactive guard on purpose; see bootstrap.sh.'
        echo '. /etc/profile.d/0x58-build-env.sh'
        echo
        cat "$rc" 2>/dev/null || true
    } > "$tmp"
    install -m 644 -o "$USER_NAME" -g "$USER_NAME" "$tmp" "$rc"
    rm -f "$tmp"
}

# ── build-env: one command that says what this box actually has ──────────────
# The handoff needs a way to answer "is the toolchain there" that is not five
# `command -v` calls typed from memory. It reports versions, not presence: an
# empty PATH entry and a missing tool look identical to `command -v` under a
# shell that never sourced the profile.
install_build_env_report() {
    cat > /usr/local/bin/build-env <<'REPORT'
#!/usr/bin/env bash
# Print the build toolchain and its versions. Exit 1 if anything required is missing.
missing=0
row() {
    local name="$1" ver
    shift
    if ver=$("$@" 2>&1 | head -1); then
        printf '  %-14s %s\n' "$name" "$ver"
    else
        printf '  %-14s MISSING\n' "$name"
        missing=1
    fi
}
echo "host: $(hostname)  |  $(nproc) vCPU  |  $(free -g | awk '/^Mem:/{print $2}') GB RAM  |  $(df -h --output=avail / | tail -1 | tr -d ' ') free on /"
echo "toolchain:"
row java    java -version
row javac   javac -version
row docker  docker --version
row compose docker-compose --version
row git     git --version
row rsync   rsync --version
row tmux    tmux -V
# --version first, then `version`: go and kubectl answer the subcommand, task and
# kind answer the flag, and asking task for `version` prints a Taskfile error
# that reads as a broken install rather than a missing argument.
for opt in go task kubectl helm kind; do
    command -v "$opt" >/dev/null || continue
    ver=$("$opt" --version 2>/dev/null | head -1) || true
    [ -n "$ver" ] || ver=$("$opt" version 2>&1 | head -1)
    printf '  %-14s %s\n' "$opt" "$ver"
done
echo "gradle:   ./gradlew is the source of truth; user overrides in ~/.gradle/gradle.properties"
exit "$missing"
REPORT
    chmod 0755 /usr/local/bin/build-env
}

# Everything below is first-boot only. dockerd returns via systemd on reboot and
# the toolchain lives on disk, so a reboot has nothing to reconcile but tmux.
if first_boot; then
    # ── apt: docker, a compose provider, and the tools rsync/gradle need ─────
    # docker.io, NOT rootless podman. The devbox runs podman behind a shim
    # because it is a multi-tenant workstation; this box runs one workload and a
    # real /var/run/docker.sock is what testcontainers and buildx expect.
    #
    # That also inverts the warning in linux/packages.txt: there, docker-compose
    # is excluded because it Recommends docker-cli, and a real /usr/bin/docker
    # would shadow the podman shim and talk to a socket that does not exist.
    # Here the socket DOES exist and the real docker CLI is the intended one, so
    # the recommendation is welcome rather than dangerous.
    #
    # rsync is not optional: it is the transport for the whole handoff, and the
    # devbox end fails with a bare "connection unexpectedly closed" when the
    # remote binary is absent -- which reads as a network fault, not a missing
    # package.
    log "installing docker, compose, and build prerequisites"
    apt-get update -qq || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        docker.io docker-compose git rsync tmux build-essential \
        ca-certificates curl unzip zip \
        || log "apt install FAILED — box is on the tailnet, finish by hand"

    usermod -aG docker "$USER_NAME" || log "could not add $USER_NAME to docker group"
    systemctl enable --now docker || log "docker failed to start (non-fatal)"

    install_build_env
    install_build_env_report

    # ── mise + JDK 21 ────────────────────────────────────────────────────────
    # Temurin 21 specifically, because that is the JDK the walt.id build was
    # verified against on the devbox on 2026-09-03. Debian's openjdk-21-jdk is
    # the fallback rather than the default: both are OpenJDK builds and would
    # almost certainly behave the same, but "almost certainly" is not a thing to
    # discover halfway through a multi-day test run.
    #
    # Only the tools this box needs, NOT dotfiles/mise/config.toml. That config
    # installs ~60 tools in ~15 minutes for a workstation; this node compiles
    # Kotlin and builds images.
    log "installing mise"
    if as_user 'curl -fsSL https://mise.run | sh'; then
        as_user 'mkdir -p ~/.config/mise'
        cat > "$USER_HOME/.config/mise/config.toml" <<'MISE'
# testbox — deliberately minimal; see roles/testbox/bootstrap.sh.
[tools]
java = "temurin-21"   # the JDK the walt.id build was verified against
go   = "latest"       # the iden2 services alongside it are Go
task = "latest"       # Taskfile targets in both repos

# Not optional here: this box RUNS the cluster it tests against, so kind builds
# it and kubectl/helm drive it. kubectl is pinned; the other two float because a
# stale pin fails to download long after anyone remembers this file exists.
kubectl = "1.36"
helm    = "latest"
kind    = "latest"
MISE
        chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config/mise"
        as_user 'mise trust ~/.config/mise/config.toml' >/dev/null 2>&1 || true
        if as_user 'mise install'; then
            log "mise toolchain installed"
        else
            log "mise install FAILED — falling back to Debian's JDK"
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-21-jdk \
                || log "openjdk-21-jdk ALSO failed — no JDK on this box"
        fi
    else
        log "mise installer FAILED — installing Debian's JDK instead"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-21-jdk \
            || log "openjdk-21-jdk failed — no JDK on this box"
    fi

    # ── Gradle memory budget for THIS plan ───────────────────────────────────
    # A user-level gradle.properties, which beats the one in the repo: Gradle
    # searches GRADLE_USER_HOME before the project directory and takes the first
    # value it finds. So this tunes the machine without touching the tree, and
    # nothing here shows up in a `git status` the agent has to explain.
    #
    # The split below is a budget, not a maximum. 16 GB has to hold the Gradle
    # daemon, the Kotlin compile daemon, and a docker build, all resident at the
    # same time -- so the JVMs are held to 10 GB and the rest is left for the
    # builder and the page cache. Raising either number past that trades an OOM
    # kill for a swap storm.
    log "writing gradle memory budget for $(nproc) vCPU / $(free -g | awk '/^Mem:/{print $2}') GB"
    as_user 'mkdir -p ~/.gradle'
    cat > "$USER_HOME/.gradle/gradle.properties" <<'GRADLE'
# 0x58 testbox. Sized for the plan it is CURRENTLY on, not the floor.
# Machine tuning only. Anything the BUILD needs belongs in the repo's own file.
org.gradle.jvmargs=-Xmx6g -XX:MaxMetaspaceSize=1g -XX:+HeapDumpOnOutOfMemoryError
kotlin.daemon.jvmargs=-Xmx4g

# 6 of 8 cores, leaving two for dockerd and the OS. Full parallelism starves the
# image build that usually follows the compile in the same session.
org.gradle.workers.max=6
org.gradle.parallel=true
org.gradle.caching=true

# The daemon is the point on a box that builds all day: it keeps the JIT warm
# between invocations. Three hours, so an idle overnight box releases the heap.
org.gradle.daemon=true
org.gradle.daemon.idletimeout=10800000
GRADLE
    chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.gradle"

    as_user 'mkdir -p ~/src' || true

    # ── kind cluster, bound to the TAILNET address ───────────────────────────
    # This is the step that CANNOT be retrofitted, and the reason it happens at
    # first boot rather than on demand. kind binds its API server to 127.0.0.1
    # by default, so the kubeconfig it emits is useless from the devbox and the
    # serving cert carries no SAN for any other address. Both are settled when
    # the cluster is created and never afterwards -- fixing it later means
    # destroying the cluster. Same reasoning, same code, as roles/k8s.
    #
    # The devbox reaches 6443 because the ACL already grants
    # `tag:devbox -> tag:k8s:6443,22`.
    TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
    if [ -z "$TS_IP" ]; then
        log "no tailscale IPv4 yet — skipping cluster creation; rerun node-bootstrap later"
    else
        CFG="$USER_HOME/kind-cluster.yaml"
        cat > "$CFG" <<YAML
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  # Tailnet address of this node. Puts the address in the serving cert's SANs
  # and lets kubectl on the devbox reach the API server.
  apiServerAddress: "$TS_IP"
  apiServerPort: 6443
nodes:
  - role: control-plane
YAML
        chown "$USER_NAME:$USER_NAME" "$CFG"

        # Non-fatal by design: a failure here still leaves a reachable box with
        # kind installed, which is debuggable. An unreachable box is not.
        if as_user "kind get clusters 2>/dev/null | grep -qx '${CLUSTER_NAME:-dev}'"; then
            log "cluster '${CLUSTER_NAME:-dev}' already exists"
        else
            log "creating kind cluster '${CLUSTER_NAME:-dev}' (pulls a ~1GB node image)"
            as_user "kind create cluster --name '${CLUSTER_NAME:-dev}' --config '$CFG'" \
                || log "kind create FAILED — by hand: kind create cluster --config $CFG"
        fi
    fi
fi

# ── A tmux session waiting to be attached (EVERY boot) ───────────────────────
# Same reason as the devbox role: a long build must survive the ssh connection
# that started it, and tmux dies with the machine, so this cannot be first-boot
# only. `sandbox-ssh testbox -t tmux attach -t main` is the way in.
if ! as_user 'tmux has-session -t main 2>/dev/null'; then
    log "creating detached tmux session 'main'"
    as_user 'tmux new-session -d -s main' || log "tmux session create failed (non-fatal)"
fi

log "testbox bootstrap done"
