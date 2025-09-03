#!/bin/bash

set -euo pipefail

if [ "${DEBUG_LEVEL:-0}" -gt 0 ]; then
  set -x
fi

echo "Checking GitHub App integration..."

# Validate required variables
required_vars=(
  CERTORA_LOG_DIR
  GROUP_ID
  CERTORA_API_SUBDOMAIN
  ACTIONS_ID_TOKEN_REQUEST_TOKEN
  ACTIONS_ID_TOKEN_REQUEST_URL
  GITHUB_EVENT_PATH
)

missing_args=false

for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "::error title=Missing variable::$var is required but not set"
    missing_args=true
  fi
done

if [ "$missing_args" = true ]; then
  exit 1
fi

GHINT_LOG="$CERTORA_LOG_DIR/gh-int.json"

CERT_GH_APP_LINK='https://github.com/apps/certora-run'
CERT_GH_ACTION_LINK='https://github.com/Certora/certora-run-action'

# Fetch OIDC token
TOKEN="$(curl -sSfL --retry 3 --max-time 30 -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r .value)"
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "::error title=Token Retrieval Failed::Could not fetch GitHub OIDC token."
  exit 1
fi

PR_NUMBER="$(jq --raw-output '.pull_request.number' "$GITHUB_EVENT_PATH")"

ERROR_MSG="Please install the Certora GitHub App ($CERT_GH_APP_LINK) and follow the guide from Certora GitHub Action ($CERT_GH_ACTION_LINK)."

# JSON payload
PAYLOAD=$(jq -n \
  --arg group_id "$GROUP_ID" \
  --arg commit "$COMMIT_SHA" \
  --arg action_ref "$CERTORA_ACTION_REF" \
  --argjson pr_number "${PR_NUMBER:-null}" \
  '{group_id: $group_id, commit: $commit, action_ref: $action_ref, pr_number: $pr_number}')

# Make API request to verify GitHub App integration
curl -sSL --proto '=https' --tlsv1.2 --retry 10 --max-time 60 --retry-connrefused --fail-with-body -X POST "https://$CERTORA_API_SUBDOMAIN.certora.com/v1/github-app/verify" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >"$GHINT_LOG" || {
  echo "::error title=Certora GitHub Application Integration Missing::$(jq -r '"Error \(.status_code): \(.detail)"' "$GHINT_LOG") - $ERROR_MSG"
  cat "$GHINT_LOG"
  exit 1
}
