# devcontainer-features

Dev Container Features for pflege-de. Each feature lives in `src/<feature>/`.

## agent-token

Client scripts for [token-broker](https://github.com/pflege-de/token-broker): a coding agent gets
short-lived tokens of a dedicated agent GitHub App instead of the developer's credentials. Tokens
are fetched on demand, per repo, at the moment git, gh or the GitHub MCP server need one. Agent
tokens live 1h and cover one repo, while sessions run longer and touch several repos.

| Script (`src/agent-token/bin/`) | Role |
|---|---|
| `agent-token` | Device-flow login (`--login`), login check (`--check`), token per repo with a cache |
| `agent-token-git-credential` | git credential helper for `github.com` |
| `agent-gh` | Wrapper installed as `gh`; sets `GH_TOKEN` for the target repo |
| `agent-github-mcp` | Starts the local `github-mcp-server` with a token for the current repo (optional) |
| `agent-commit` | Commits the staged changes through the GitHub API, so GitHub signs them (optional) |

The developer logs in once per 8h with `agent-token --login` in an interactive terminal. All other
calls set `AGENT_TOKEN_NONINTERACTIVE=1` and fail with `run: agent-token --login` instead of
waiting for a device code nobody sees.

Environment: `TOKEN_BROKER_URL` (internal broker URL) and `LOGIN_APP_CLIENT_ID` (client ID of the
login app). The pflege-de orgs publish both as the Actions variables `AGENT_TOKEN_BROKER_URL` and
`AGENT_LOGIN_CLIENT_ID` (repo variables override them); token-broker's
[`.devcontainer/broker-env.sh`](https://github.com/pflege-de/token-broker/blob/main/.devcontainer/broker-env.sh)
reads them on the host and passes them into the container.

### Signed commits

`git commit` in the container makes unsigned commits: GitHub signs app commits only when it
creates them itself. Rulesets with `required_signatures` then block them on protected branches
(squash merges still work, GitHub signs the squash commit). `agent-commit` instead sends the
staged changes to GraphQL `createCommitOnBranch` and moves the local branch onto the signed
commit:

```sh
git add -A
agent-commit -m "feat: something" -m "Body."   # or -F <file>
```

- It pushes as it commits; there is no separate `git push`. A branch missing on origin is created
  at `HEAD`, which must already be on GitHub.
- It refuses if the local branch has commits that origin lacks, and for new executables or mode
  changes: the API has no file mode, so new files land as `100644`. Commit those with `git commit`.
- No merge commits; rebase onto the base branch instead.
- `AGENT_COMMIT_MODE=local` turns it into plain `git commit`, for repos that do not want API
  commits.

Live test: `test/agent-commit.sh org/repo` (needs a login and write access; cleans up its branch).

### On the host

Requirements: `bash`, `curl`, `jq`. Clone this repo and put `src/agent-token/bin` on your `PATH`
(token-broker's `agent-run` finds `agent-token` there), or call the script directly:

```sh
agent-token my-org/my-repo   # prints a 1h agent token
```

The login token is cached in `~/.cache/agent-token/login.json` (mode 600) for 8 hours. Without a
container, deny the agent read access to `~/.ssh`, `~/.config/gh` and `~/.cache/agent-token`.

### In an image

- `bash`, `curl`, `jq`, `git`, `gh`; `github-mcp-server` only for the MCP server.
- The scripts in `/usr/local/bin`, with `agent-gh` installed **as `gh`**. It must come before the
  real `gh` in `PATH`; the wrapper finds the real one itself.
- `TOKEN_BROKER_URL` and `LOGIN_APP_CLIENT_ID` in the environment.
- System git config:

  ```sh
  # The empty value drops inherited helpers (store, osxkeychain, gh) for github.com.
  git config --system credential.https://github.com.helper ''
  git config --system --add credential.https://github.com.helper '!agent-token-git-credential'
  # Without the path git cannot say which repo it needs a token for.
  git config --system credential.https://github.com.useHttpPath true
  # Credential helpers only work over HTTPS.
  git config --system url.https://github.com/.insteadOf git@github.com:
  git config --system --add url.https://github.com/.insteadOf ssh://git@github.com/
  ```

- A volume for `~/.cache/agent-token`, so the login survives container restarts. It holds the
  developer's login token (8h) and agent tokens (1h); keep it per developer, never shared.

Do not run `gh auth login` or `gh auth setup-git` in the container: the agent should act only as
the agent app. Commands without one target repo (`gh api orgs/...`) get no agent token and fail
unauthenticated, by design.

Until the feature is published, fetch the scripts at a pinned commit:

```dockerfile
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends bash ca-certificates curl git gh jq \
 && rm -rf /var/lib/apt/lists/*
ARG AGENT_TOKEN_REF=<commit of this repo>
RUN base=https://raw.githubusercontent.com/pflege-de-labs/devcontainer-features/$AGENT_TOKEN_REF/src/agent-token/bin \
 && for f in agent-token agent-token-git-credential agent-github-mcp agent-commit; do curl -fsSL "$base/$f" -o /usr/local/bin/$f; done \
 && curl -fsSL "$base/agent-gh" -o /usr/local/bin/gh \
 && chmod 755 /usr/local/bin/agent-token /usr/local/bin/agent-token-git-credential /usr/local/bin/agent-github-mcp /usr/local/bin/agent-commit /usr/local/bin/gh
RUN git config --system credential.https://github.com.helper '' \
 && git config --system --add credential.https://github.com.helper '!agent-token-git-credential' \
 && git config --system credential.https://github.com.useHttpPath true \
 && git config --system url.https://github.com/.insteadOf git@github.com: \
 && git config --system --add url.https://github.com/.insteadOf ssh://git@github.com/
ENV TOKEN_BROKER_URL=https://token-broker.internal \
    LOGIN_APP_CLIENT_ID=<login app client ID>
```

Debian's `gh` lands in `/usr/bin`, after `/usr/local/bin` in `PATH`. Add Claude Code and your
toolchain as usual.

```sh
podman build -t agent-dev .
podman volume create agent-token-cache
podman run -it --name agent-dev \
  -v agent-token-cache:/root/.cache/agent-token \
  -v "$PWD":/work -w /work agent-dev bash
# inside, once per 8h:
agent-token --login
```

From another terminal: `podman exec -it agent-dev agent-token --login`.

A complete devcontainer (egress firewall, Claude Code managed settings, VS Code credential
forwarding closed) is token-broker's [`.devcontainer/`](https://github.com/pflege-de/token-broker/tree/main/.devcontainer),
described in its [docs/containers.md](https://github.com/pflege-de/token-broker/blob/main/docs/containers.md).
