# Development Tools

Generated: 2026-05-01

Source of truth: [`../dotfiles/mise/config.toml`](../dotfiles/mise/config.toml)
(symlinked to `~/.config/mise/config.toml`)

## mise-managed tools

```
actionlint                               v1.7.11
actionlint                               1.7.11    ~/.config/mise/config.toml  latest
air                                      1.52.3    ~/.config/mise/config.toml  latest
aqua:securego/gosec                      2.25.0    ~/.config/mise/config.toml  latest
ast-grep                                 0.42.1    ~/.config/mise/config.toml  latest
awscli                                   2.34.38   ~/.config/mise/config.toml  latest
bat                                      0.26.1    ~/.config/mise/config.toml  latest
checkov                                  3.2.524   ~/.config/mise/config.toml  latest
cloud-sql-proxy                          2.21.3    ~/.config/mise/config.toml  latest
cloudflared                              2026.3.0  ~/.config/mise/config.toml  latest
codex                                    0.125.0   ~/.config/mise/config.toml  0.125.0
ctop                                     0.7.7     ~/.config/mise/config.toml  latest
dive                                     0.13.1    ~/.config/mise/config.toml  latest
fd                                       10.4.2    ~/.config/mise/config.toml  latest
firebase                                 15.15.0   ~/.config/mise/config.toml  latest
fzf                                      0.71.0    ~/.config/mise/config.toml  latest
gh                                       2.91.0    ~/.config/mise/config.toml  latest
github:go-acme/lego                      4.35.2    ~/.config/mise/config.toml  latest
github:golang-migrate/migrate            4.19.1    ~/.config/mise/config.toml  latest
glow                                     2.1.2     ~/.config/mise/config.toml  latest
go                                       1.26.2    ~/.config/mise/config.toml  1.26
go:github.com/swaggo/swag/cmd/swag       1.16.4
go:golang.org/x/tools/cmd/goimports      0.39.0    ~/.config/mise/config.toml  latest
go:golang.org/x/vuln/cmd/govulncheck     1.1.4     ~/.config/mise/config.toml  latest
golangci-lint                            2.11.4    ~/.config/mise/config.toml  latest
gotestsum                                1.11.0    ~/.config/mise/config.toml  latest
hadolint                                 2.14.0    ~/.config/mise/config.toml  latest
helm                                     4.1.4     ~/.config/mise/config.toml  latest
jq                                       1.7.1     ~/.config/mise/config.toml  latest
jwt                                      6.2.0     ~/.config/mise/config.toml  latest
kind                                     0.31.0    ~/.config/mise/config.toml  latest
krew                                     0.5.0     ~/.config/mise/config.toml  latest
kubectl                                  1.35.4
kubectl                                  1.36.0    ~/.config/mise/config.toml  1.36
kubectx                                  0.11.0    ~/.config/mise/config.toml  latest
lefthook                                 v2.0.9    ~/.config/mise/config.toml  latest
mkcert                                   1.4.4     ~/.config/mise/config.toml  latest
neovim                                   0.12.2    ~/.config/mise/config.toml  latest
node                                     22.17.1   ~/.config/mise/config.toml  22
npm                                      10.9.2
npm:@openapitools/openapi-generator-cli  2.31.1    ~/.config/mise/config.toml  latest
npm:@redocly/cli                         2.22.1    ~/.config/mise/config.toml  latest
npm:@stoplight/spectral-cli              6.15.0    ~/.config/mise/config.toml  latest
npm:esbuild                              0.28.0    ~/.config/mise/config.toml  latest
packer                                   1.15.2    ~/.config/mise/config.toml  latest
pnpm                                     10.33.2   ~/.config/mise/config.toml  latest
pre-commit                               4.6.0     ~/.config/mise/config.toml  latest
prettier                                 3.8.3     ~/.config/mise/config.toml  latest
python                                   3.12.13   ~/.config/mise/config.toml  3.12
ripgrep                                  15.1.0    ~/.config/mise/config.toml  latest
shellcheck                               0.11.0    ~/.config/mise/config.toml  latest
stern                                    1.33.1    ~/.config/mise/config.toml  latest
swag                                     1.16.6    ~/.config/mise/config.toml  latest
task                                     3.48.0    ~/.config/mise/config.toml  latest
temporal                                 1.30.4    ~/.config/mise/config.toml  latest
terraform                                1.14.6    ~/.config/mise/config.toml  1.14
tflint                                   0.50.3    ~/.config/mise/config.toml  latest
tfsec                                    1.28.14   ~/.config/mise/config.toml  latest
ubi:go-acme/lego                         4.35.2
ubi:golang-migrate/migrate               v4.19.1
uv                                       0.10.8    ~/.config/mise/config.toml  latest
wrangler                                 4.85.0    ~/.config/mise/config.toml  latest
yamllint                                 1.38.0    ~/.config/mise/config.toml  latest
yq                                       4.52.4    ~/.config/mise/config.toml  latest
```

## npm globals

```
/Users/arbeitandy/.local/share/mise/installs/node/22.17.1/lib
├── corepack@0.33.0
└── npm@10.9.2

```

## Key tool notes

- **mise** — single source of truth for dev tools (node, go, terraform, kubectl, etc.)
- **brew** — system libs, GUI casks, macOS-specific tools only
- **OrbStack** — container runtime (Docker-compatible, paying user)
- **Secretive** — SSH agent backed by Secure Enclave hardware keys
- **GPG signing** enabled for git commits
- **Release-age buffer** — 3 days for both mise and pnpm/npm
