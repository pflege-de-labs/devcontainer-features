# devcontainer-features

Dev Container Features for pflege-de. Each feature lives in `src/<feature>/`.

## agent-token

Installs the client scripts of [token-broker](https://github.com/pflege-de-labs/token-broker)
(`agent-token`, its git credential helper, the `gh` wrapper, `agent-github-mcp`, `agent-commit`),
so git, gh and the GitHub MCP server act as the agent GitHub App with short-lived tokens instead of
the developer's credentials. The scripts and their docs live in token-broker's
[`client/`](https://github.com/pflege-de-labs/token-broker/tree/main/client); each token-broker
release attaches them as a tarball (token-broker ADR 14).

```jsonc
"features": {
  "ghcr.io/pflege-de-labs/devcontainer-features/agent-token:1": {}
},
// TOKEN_BROKER_URL, e.g. written by token-broker's broker-env.sh.
"runArgs": ["--env-file=${localWorkspaceFolder}/.devcontainer/.env"],
"mounts": ["source=agent-token-cache-${devcontainerId},target=/home/vscode/.cache/agent-token,type=volume"],
"postAttachCommand": "agent-token --check 2>/dev/null || agent-token --login"
```

| Option | Default | |
|---|---|---|
| `version` | pinned release | token-broker release to install, e.g. `0.6.0`. The pinned one is checked against a sha256 reviewed in this repo; any other only against its release's `checksums.txt`. |

The feature downloads the release tarball from GitHub, installs `curl`, `jq`, `git` and `gh` if
missing (apt only), puts the scripts in `/usr/local/share/agent-token/bin` ahead of everything else
in `PATH` (so `gh` is the wrapper) and writes the system git config the credential helper needs.
After creation it sets `core.checkStat minimal` in the workspace repo: host and container see
different inode/uid data through the bind mount, so each side's `git status` (also an editor's on
the host) would rewrite the index, and the other side then briefly reads it as missing, i.e. empty.
Change the mount target to your `remoteUser`'s home.

New scripts reach devcontainers by bumping `pinned_version` and `pinned_sha256` in `install.sh`
(from the release's `checksums.txt`) together with the feature `version`; the release skips an
unchanged `version`.

Test: `devcontainer features test -f agent-token -i mcr.microsoft.com/devcontainers/base:bookworm`
(with podman, put a `docker` symlink to `podman` first in `PATH`).
