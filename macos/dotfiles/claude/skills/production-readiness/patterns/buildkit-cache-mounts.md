# BuildKit Cache Mounts

## Problem

Standard Docker layer caching is all-or-nothing: if `go.sum` or `package-lock.json` changes, the entire `RUN go mod download` or `RUN npm ci` layer re-executes from scratch — even if only one dependency changed.

## Solution

BuildKit `--mount=type=cache` persists a directory across builds inside the BuildKit daemon. Even when the Docker layer cache misses, the underlying files (downloaded modules, compiled objects) are retained.

## Go Pattern

```dockerfile
# Module download — cache persists downloaded .zip/.mod files
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Build — cache persists compiled object files
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -o /app ./cmd/server
```

Both mounts are needed on `go build` because the Go toolchain reads modules from `/go/pkg/mod` and writes/reads compilation cache from the build cache.

## Node.js Pattern

```dockerfile
# npm stores its HTTP response cache in ~/.npm
RUN --mount=type=cache,target=/root/.npm \
    npm ci
```

## Interaction with other caching layers

| Layer | Scope | Granularity | When it helps |
|---|---|---|---|
| Docker layer cache | Per `RUN` instruction | All-or-nothing | Lockfile unchanged |
| GHA cache (`type=gha`) | Per workflow scope | Per layer | CI rebuilds |
| BuildKit cache mount | Per target directory | Per file | Partial lockfile changes |
| docker-compose volumes | Runtime containers | Per file | Local dev hot-reload |

**Cache mounts and docker-compose volumes do not conflict.** Cache mounts are build-time only (during `docker build`). Docker-compose named volumes are runtime only (mounted into running containers). They operate at completely different layers even when targeting the same logical cache (e.g., Go module cache).

## CI Compatibility

Cache mounts work automatically with existing `docker/setup-buildx-action` + GHA cache. No workflow changes needed. The GHA layer cache handles cross-build layer reuse; cache mounts handle intra-layer file reuse when layers are invalidated.

## Cache mount is invisible in the final image

Unlike `COPY` or `RUN` with regular writes, `--mount=type=cache` content is never baked into any Docker layer. The final image size is unchanged.
