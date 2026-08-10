# Development Tools

Generated: 2026-07-17

Source of truth: [`../dotfiles/mise/config.toml`](../dotfiles/mise/config.toml)
(symlinked to `~/.config/mise/config.toml`)

## mise-managed tools

```
actionlint                               1.7.12    ~/.config/mise/config.toml  latest
air                                      1.65.3    ~/.config/mise/config.toml  latest
aqua:securego/gosec                      2.27.1    ~/.config/mise/config.toml  latest
ast-grep                                 0.44.1    ~/.config/mise/config.toml  latest
awscli                                   2.35.23   ~/.config/mise/config.toml  latest
bat                                      0.26.1    ~/.config/mise/config.toml  latest
checkov                                  3.3.8     ~/.config/mise/config.toml  latest
cloud-sql-proxy                          2.23.0    ~/.config/mise/config.toml  latest
cloudflared                              2026.7.1  ~/.config/mise/config.toml  latest
codex                                    0.144.1   ~/.config/mise/config.toml  0.144.1
ctop                                     0.7.7     ~/.config/mise/config.toml  latest
dive                                     0.13.1    ~/.config/mise/config.toml  latest
fd                                       10.4.2    ~/.config/mise/config.toml  latest
firebase                                 15.23.0   ~/.config/mise/config.toml  latest
fzf                                      0.74.0    ~/.config/mise/config.toml  latest
gh                                       2.96.0    ~/.config/mise/config.toml  latest
github:go-acme/lego                      5.2.2     ~/.config/mise/config.toml  latest
github:golang-migrate/migrate            4.19.1    ~/.config/mise/config.toml  latest
glow                                     2.1.2     ~/.config/mise/config.toml  latest
go                                       1.26.5    ~/.config/mise/config.toml  1.26
go:golang.org/x/tools/cmd/goimports      0.48.0    ~/.config/mise/config.toml  latest
go:golang.org/x/vuln/cmd/govulncheck     1.6.0     ~/.config/mise/config.toml  latest
golangci-lint                            2.12.2    ~/.config/mise/config.toml  latest
gotestsum                                1.13.0    ~/.config/mise/config.toml  latest
hadolint                                 2.14.0    ~/.config/mise/config.toml  latest
helm                                     4.2.3     ~/.config/mise/config.toml  latest
jq                                       1.8.2     ~/.config/mise/config.toml  latest
jwt                                      6.2.0     ~/.config/mise/config.toml  latest
kind                                     0.32.0    ~/.config/mise/config.toml  latest
krew                                     0.5.0     ~/.config/mise/config.toml  latest
kubectl                                  1.36.2    ~/.config/mise/config.toml  1.36
kubectx                                  0.11.0    ~/.config/mise/config.toml  latest
lefthook                                 2.1.10    ~/.config/mise/config.toml  latest
mkcert                                   1.4.4     ~/.config/mise/config.toml  latest
neovim                                   0.12.4    ~/.config/mise/config.toml  latest
node                                     22.23.1   ~/.config/mise/config.toml  22
npm:@openapitools/openapi-generator-cli  2.39.1    ~/.config/mise/config.toml  latest
npm:@redocly/cli                         2.38.0    ~/.config/mise/config.toml  latest
npm:@stoplight/spectral-cli              6.16.1    ~/.config/mise/config.toml  latest
npm:esbuild                              0.28.1    ~/.config/mise/config.toml  latest
packer                                   1.15.4    ~/.config/mise/config.toml  latest
pnpm                                     11.12.0   ~/.config/mise/config.toml  latest
pre-commit                               4.6.0     ~/.config/mise/config.toml  latest
prettier                                 3.9.5     ~/.config/mise/config.toml  latest
python                                   3.12.13   ~/.config/mise/config.toml  3.12
ripgrep                                  15.1.0    ~/.config/mise/config.toml  latest
shellcheck                               0.11.0    ~/.config/mise/config.toml  latest
stern                                    1.34.0    ~/.config/mise/config.toml  latest
swag                                     1.16.6    ~/.config/mise/config.toml  latest
task                                     3.52.0    ~/.config/mise/config.toml  latest
temporal                                 1.31.2    ~/.config/mise/config.toml  latest
terraform                                1.14.9    ~/.config/mise/config.toml  1.14
tflint                                   0.63.1    ~/.config/mise/config.toml  latest
tfsec                                    1.28.14   ~/.config/mise/config.toml  latest
uv                                       0.11.28   ~/.config/mise/config.toml  latest
wrangler                                 4.110.0   ~/.config/mise/config.toml  latest
yamllint                                 1.38.0    ~/.config/mise/config.toml  latest
yq                                       4.53.3    ~/.config/mise/config.toml  latest
```

## npm globals

```
/Users/arbeitandy/.local/share/mise/installs/node/22.23.1/lib
├── corepack@0.34.6
└── npm@10.9.8

```

## Key tool notes

- **mise** — single source of truth for dev tools (node, go, terraform, kubectl, etc.)
- **brew** — system libs, GUI casks, macOS-specific tools only
- **Secretive** — SSH agent backed by Secure Enclave hardware keys
- **GPG signing** enabled for git commits
- **Release-age buffer** — 3 days for both mise and pnpm/npm
