#!/usr/bin/env bash
# Live test for agent-commit: needs agent-token logged in and write access to <org/repo>.
# Usage: test/agent-token/agent-commit-live.sh org/repo  — works on a throwaway branch and deletes it afterwards.
set -euo pipefail
repo=${1:?usage: test/agent-token/agent-commit-live.sh org/repo}
PATH=$(cd "$(dirname "$0")/../../src/agent-token/bin" && pwd):$PATH
token=$(AGENT_TOKEN_NONINTERACTIVE=1 agent-token "$repo")
gh_api() { curl -fsS -H "Authorization: Bearer $token" "https://api.github.com/repos/$repo/$1" "${@:2}"; }
branch=test/agent-commit-$(date +%s)
dir=$(mktemp -d)
trap 'gh_api "git/refs/heads/$branch" -X DELETE || true; rm -rf "$dir"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

git clone -q --depth 1 "https://github.com/$repo" "$dir"
cd "$dir"
git switch -q -c "$branch"
victim=$(git ls-files | head -1)

# New remote branch, addition, modification, deletion.
echo new >added.txt
echo more >>README.md
git rm -q "$victim"
git add added.txt README.md
agent-commit -m "test: first" -m "body line"
[[ $(git rev-parse HEAD) == $(git rev-parse "origin/$branch") ]] || fail "HEAD not on origin"
[[ -z $(git status --porcelain) ]] || fail "worktree not clean"
[[ $(gh_api "commits/$(git rev-parse HEAD)" | jq .commit.verification.verified) == true ]] || fail "not verified"
[[ $(git log -1 --format=%b) == "body line" ]] || fail "body lost"

# Existing remote branch.
echo again >>added.txt
git add added.txt
agent-commit -m "test: second"
[[ $(git rev-parse HEAD~1) == $(git rev-parse "origin/$branch~1") && $(git rev-parse HEAD) == $(git rev-parse "origin/$branch") ]] ||
  fail "second commit not on origin"

# A new executable would silently lose +x.
printf '#!/bin/sh\n' >run.sh && chmod +x run.sh && git add run.sh
agent-commit -m "test: exec" 2>/dev/null && fail "accepted a new executable"
git reset -q run.sh && rm run.sh

# Local commits ahead of origin cannot be replayed.
git commit -q --allow-empty -m local
echo x >>added.txt && git add added.txt
agent-commit -m "test: ahead" 2>/dev/null && fail "accepted a local commit ahead of origin"

echo "agent-commit: all tests passed"
