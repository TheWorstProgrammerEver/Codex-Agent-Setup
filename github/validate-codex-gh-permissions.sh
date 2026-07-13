#!/usr/bin/env bash
set -euo pipefail

permissions_json='{"contents":"write","pull_requests":"write","issues":"write"}'

usage() {
  cat <<'EOF'
Usage: ./github/validate-codex-gh-permissions.sh OWNER/REPO

Validates that codex-gh passes CODEX_GH_PERMISSIONS_JSON through to
codex-github-token without printing or storing a token.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

repo="${1:?missing OWNER/REPO}"

case "$repo" in
  */*) ;;
  *)
    printf 'Repository must be OWNER/REPO, got: %s\n' "$repo" >&2
    exit 2
    ;;
esac

printf 'Checking token expiry with custom permissions...\n'
codex-github-token --permissions-json "$permissions_json" --repo "$repo" --expires-at

printf 'Checking codex-gh with CODEX_GH_PERMISSIONS_JSON...\n'
CODEX_GH_REPO="$repo" \
CODEX_GH_PERMISSIONS_JSON="$permissions_json" \
  codex-gh api "repos/$repo" --jq .full_name

printf 'Validation complete; no token value was requested or printed.\n'
