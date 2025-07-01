#!/bin/bash

set -euo pipefail

if [ "${DEBUG_LEVEL:-0}" -gt 0 ]; then
  set -x
fi

echo "Checking GitHub App integration..."

# Validate required variables
: "${CERTORA_LOG_DIR:?Missing CERTORA_LOG_DIR}"
: "${GROUP_ID:?Missing GROUP_ID}"
: "${CERTORA_SUBDOMAIN:?Missing CERTORA_SUBDOMAIN}"
: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?Missing ACTIONS_ID_TOKEN_REQUEST_TOKEN}"
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?Missing ACTIONS_ID_TOKEN_REQUEST_URL}"
: "${GITHUB_EVENT_PATH:?Missing GITHUB_EVENT_PATH}"

GHINT_LOG="$CERTORA_LOG_DIR/gh-int.json"

# Fetch OIDC token
TOKEN="$(curl -sf -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r .value)"
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "::error title=Token Retrieval Failed::Could not fetch GitHub OIDC token."
  exit 1
fi

PR_NUMBER="$(jq --raw-output '.pull_request.number' "$GITHUB_EVENT_PATH")"
COMMIT="$GITHUB_SHA"

# JSON payload
PAYLOAD=$(jq -n \
  --arg group_id "$GROUP_ID" \
  --arg repo "$GITHUB_REPOSITORY" \
  --arg commit "$COMMIT" \
  --argjson pr_number "${PR_NUMBER:-null}" \
  '{group_id: $group_id, repo: $repo, commit: $commit, pr_number: $pr_number}')

# Make API request to verify GitHub App integration
curl -sSL --proto '=https' --tlsv1.2 --retry 10 --retry-connrefused --fail-with-body -X POST "https://$CERTORA_SUBDOMAIN.certora.com/v1/github-app/verify" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" > "$GHINT_LOG" || {
    echo "::error title=GitHub Application Integration Missing::$(jq -r '"Error \(.status_code): \(.detail)"' "$GHINT_LOG")"
    cat "$GHINT_LOG"
    exit 1
  }
