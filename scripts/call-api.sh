#!/bin/bash

set -euo pipefail

if [ "${DEBUG_LEVEL:-0}" -gt 0 ]; then
  set -x
fi

# Validate required variables
required_vars=(
  CERTORA_COMMAND
  CERTORA_API_SUBDOMAIN
  ACTIONS_ID_TOKEN_REQUEST_TOKEN
  ACTIONS_ID_TOKEN_REQUEST_URL
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

endpoint=""
group_id=""

read -r endpoint group_id <<< "$CERTORA_COMMAND"

# Fetch OIDC token
TOKEN="$(curl -sSfL --retry 3 --max-time 30 -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r .value)"
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "::error title=Token Retrieval Failed::Could not fetch GitHub OIDC token."
  exit 1
fi

# Make API request to verify GitHub App integration
curl -sSL --proto '=https' --tlsv1.2 --retry 10 --max-time 60 --retry-connrefused --fail-with-body -X POST "https://$CERTORA_API_SUBDOMAIN.certora.com/v1/github-app/$endpoint?groupId=$group_id" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" || {
  echo "::error title=Certora GitHub Application Integration Missing::$(jq -r '"Error \(.status_code): \(.detail)"' "$GHINT_LOG") - $ERROR_MSG"
  cat "$GHINT_LOG"
  exit 1
}
