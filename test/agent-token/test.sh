#!/usr/bin/env bash
# Run with: devcontainer features test -f agent-token -i mcr.microsoft.com/devcontainers/base:bookworm
# shellcheck disable=SC1091,SC2016 # the lib exists only in the test container; $ is for the inner bash
set -e
source dev-container-features-test-lib

check "scripts on PATH" bash -c 'for c in agent-token agent-token-git-credential agent-github-mcp agent-commit; do command -v $c; done'
check "gh is the wrapper" bash -c 'grep -q "gh wrapper" "$(command -v gh)"'
check "real gh behind it" bash -c '[[ $(type -ap gh | sed -n 2p) ]] && gh --version'
check "credential helper" bash -c '[[ $(git config --system --get-all credential.https://github.com.helper | tail -1) == "!agent-token-git-credential" ]]'
check "ssh rewritten to https" bash -c '[[ $(git config --system --get-all url.https://github.com/.insteadOf | head -1) == git@github.com: ]]'

reportResults
