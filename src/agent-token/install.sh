#!/usr/bin/env bash
# Installs the agent-token client scripts from a token-broker release and routes git's github.com credentials through them. See README.md.
set -euo pipefail

# Reviewed pin: the sha256 is from the release's checksums.txt; bump both together.
pinned_version=0.6.0
pinned_sha256=44717fc267594148b8d4f9722b30e636fe4fad32f2a2aa1fdd6ba64cfd2ca377
version=${VERSION:-$pinned_version}
version=${version#v}

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

base=https://github.com/pflege-de-labs/token-broker/releases/download/v$version
tarball=agent-token-$version.tar.gz
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/$tarball" "$base/$tarball"
if [[ $version == "$pinned_version" ]]; then
  sha256=$pinned_sha256
else
  # Integrity only: no sha256 for this version was reviewed here.
  sha256=$(curl -fsSL "$base/checksums.txt" | awk -v f="$tarball" '$2 == f { print $1 }')
fi
[[ -n $sha256 ]] || { echo "agent-token: no checksum for $tarball" >&2; exit 1; }
echo "$sha256  $tmp/$tarball" | sha256sum -c --quiet - || { echo "agent-token: checksum mismatch for $tarball" >&2; exit 1; }
tar -xzf "$tmp/$tarball" -C "$tmp"

# Own directory, first in PATH (containerEnv): the gh wrapper must shadow the real gh wherever it lives.
dest=/usr/local/share/agent-token/bin
install -d "$dest"
install -m 755 "$tmp"/bin/agent-token "$tmp"/bin/agent-token-git-credential "$tmp"/bin/agent-github-mcp "$tmp"/bin/agent-commit "$dest/"
install -m 755 "$tmp/bin/agent-gh" "$dest/gh"

# The empty value drops helpers inherited for github.com; useHttpPath tells the helper which repo.
git config --system credential.https://github.com.helper ''
git config --system --add credential.https://github.com.helper '!agent-token-git-credential'
git config --system credential.https://github.com.useHttpPath true
# Credential helpers only work over HTTPS.
git config --system url.https://github.com/.insteadOf git@github.com:
git config --system --add url.https://github.com/.insteadOf ssh://git@github.com/
