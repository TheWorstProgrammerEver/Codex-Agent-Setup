# GitHub App Helpers

These scripts are the source-controlled template for local GitHub App automation
helpers used by Codex-managed hosts.

They do not contain secrets. Runtime GitHub App metadata should live in
`$HOME/.config/codex-github/codex.env`, and the app private key should live in
`$HOME/.config/codex-github/app.pem` with mode `0600`.

## Install

```sh
./github/install-github-app-helpers.sh
```

This installs:

- `codex-github-token`
- `codex-github-askpass`
- `codex-gh`

## Permissions Override Validation

Run an expiry-only check first. It prints only the token expiry timestamp, not
the token value:

```sh
codex-github-token \
  --permissions-json '{"contents":"write","pull_requests":"write","issues":"write"}' \
  --expires-at
```

Then exercise the same permissions object through `codex-gh`:

```sh
CODEX_GH_REPO=OWNER/REPO \
CODEX_GH_PERMISSIONS_JSON='{"contents":"write","pull_requests":"write","issues":"write"}' \
codex-gh api repos/OWNER/REPO --jq .full_name
```

Or run the bundled validation script:

```sh
./github/validate-codex-gh-permissions.sh OWNER/REPO
```

`CODEX_GH_PERMISSIONS_JSON` is passed as one argument to
`codex-github-token --permissions-json`, so custom JSON is not appended to or
corrupted by the wrapper.
