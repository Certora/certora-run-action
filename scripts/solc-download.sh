#!/bin/bash

set -e

if [ "$DEBUG_LEVEL" -gt 0 ]; then
  set -x
fi

REMOVE_PREFIX="$1"
VERSIONS="${*:2}"
[ -z "$VERSIONS" ] && exit 0

mkdir -p /opt/solc-bin

GH_LINK='https://api.github.com/repos/argotorg/solidity/releases/tags/v'
JQ_FILTER='.assets[] | select(.name == "solc-static-linux") | .url'
AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"

# Solidity's published binary index. We verify the SHA-256 of every downloaded
# (and previously cached) compiler against this list before use. Mirrors
# github.com/ethereum/solc-bin; same approach as Foundry's svm-rs.
LIST_URL='https://binaries.soliditylang.org/linux-amd64/list.json'
LIST_JSON=$(curl -sSfL --retry 3 --max-time 30 "$LIST_URL")
if [ -z "$LIST_JSON" ]; then
  echo "Failed to fetch $LIST_URL"
  exit 1
fi

verify_sha256() {
  local v="$1" path="$2" expected actual
  expected=$(jq -r --arg v "$v" '.releases[$v] as $p | .builds[] | select(.path == $p) | .sha256' <<<"$LIST_JSON")
  if [ -z "$expected" ] || [ "$expected" = "null" ]; then
    echo "No SHA-256 reference for solc $v in $LIST_URL"
    return 1
  fi
  actual="0x$(sha256sum "$path" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "SHA-256 mismatch for solc $v: expected $expected, got $actual"
    return 1
  fi
}

FIRST_VERSION=true # Flag to track the first version

for version in $VERSIONS; do
  version="${version#v}"
  if [ -z "$REMOVE_PREFIX" ]; then
    use_version=$version
  else
    use_version="${version#"$REMOVE_PREFIX"}"
  fi

  BIN_PATH="/opt/solc-bin/solc$use_version"

  if [ ! -f "$BIN_PATH" ]; then
    echo "Downloading Solidity $version"
    RELEASE_DETAIL=$(curl -sSfL --retry 3 --max-time 30 -H "$AUTH_HEADER" "${GH_LINK}${version}")

    if [[ -z "$RELEASE_DETAIL" || $(jq 'has("assets")' <<<"$RELEASE_DETAIL") == "false" ]]; then
      echo "Failed to fetch release details for Solidity $version"
      echo "$RELEASE_DETAIL"
      exit 1
    fi
    BIN_LINK=$(jq -r "$JQ_FILTER" <<<"$RELEASE_DETAIL")

    # Download to a temp path, verify SHA-256, then move into place. Prevents
    # a partial/unverified binary from being trusted on a subsequent run.
    TMP_PATH="${BIN_PATH}.tmp.$$"
    curl -sSfL --retry 3 --max-time 90 \
      -H "Accept: application/octet-stream" \
      -H "$AUTH_HEADER" \
      "${BIN_LINK}" -o "$TMP_PATH"

    verify_sha256 "$version" "$TMP_PATH" || { rm -f "$TMP_PATH"; exit 1; }

    mv "$TMP_PATH" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    "$BIN_PATH" --version
  else
    # Re-verify cached binaries to avoid trusting a tampered cache path.
    verify_sha256 "$version" "$BIN_PATH"
  fi

  # Recreate aliases so they always point at the just-verified $BIN_PATH.
  # `-fn` avoids dereferencing an existing symlink that a restored cache may
  # have pointed elsewhere.
  if [ "$BIN_PATH" != "/opt/solc-bin/solc$version" ]; then
    ln -sfn "$BIN_PATH" "/opt/solc-bin/solc$version"
    echo "Linked: solc$version -> $BIN_PATH"
  fi
  if [ "$BIN_PATH" != "/opt/solc-bin/solc-$version" ]; then
    ln -sfn "$BIN_PATH" "/opt/solc-bin/solc-$version"
    echo "Linked: solc-$version -> $BIN_PATH"
  fi

  # Create a symlink for the first version if the binary name isn't already 'solc'
  if [ "$FIRST_VERSION" = true ] && [ "$BIN_PATH" != "/opt/solc-bin/solc" ]; then
    ln -sfn "$BIN_PATH" /opt/solc-bin/solc
    echo "Linked: solc -> solc$use_version"
    /opt/solc-bin/solc --version
    FIRST_VERSION=false
  fi
done

ls -1 /opt/solc-bin/
