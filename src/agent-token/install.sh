#!/usr/bin/env bash
# Installs the agent-token scripts and routes git's github.com credentials through them. See README.md.
set -euo pipefail
cd "$(dirname "$0")"

missing=()
for cmd in curl jq git; do command -v "$cmd" >/dev/null || missing+=("$cmd"); done
if ((${#missing[@]})) || ! command -v gh >/dev/null; then
  command -v apt-get >/dev/null || { echo "agent-token: install ${missing[*]} gh first (apt-get only)" >&2; exit 1; }
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gpg "${missing[@]}"
  if ! command -v gh >/dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli.gpg
    echo "deb [signed-by=/usr/share/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" >/etc/apt/sources.list.d/github-cli.list
    apt-get update
    apt-get install -y --no-install-recommends gh
  fi
  rm -rf /var/lib/apt/lists/*
fi

# Own directory, first in PATH (containerEnv): the gh wrapper must shadow the real gh wherever it lives.
dest=/usr/local/share/agent-token/bin
install -d "$dest"
install -m 755 bin/agent-token bin/agent-token-git-credential bin/agent-github-mcp bin/agent-commit "$dest/"
install -m 755 bin/agent-gh "$dest/gh"

# The empty value drops helpers inherited for github.com; useHttpPath tells the helper which repo.
git config --system credential.https://github.com.helper ''
git config --system --add credential.https://github.com.helper '!agent-token-git-credential'
git config --system credential.https://github.com.useHttpPath true
# Credential helpers only work over HTTPS.
git config --system url.https://github.com/.insteadOf git@github.com:
git config --system --add url.https://github.com/.insteadOf ssh://git@github.com/
