#!/bin/bash

REMOVE_PREFIX="$1"

mkdir -p /opt/solc-bin

GH_LINK='https://api.github.com/repos/ethereum/solidity/releases/tags/v'
JQ_FILTER='.assets[] | select(.name == "solc-static-linux") | .url'
AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"

for version in "${@:2}"; do
  version="${version#v}"
  if [ -z "$REMOVE_PREFIX" ]; then
    use_version=$version
  else
    use_version="${version#"$REMOVE_PREFIX"}"
  fi

  BIN_PATH="/opt/solc-bin/solc$use_version"

  if [ ! -f "$BIN_PATH" ]; then
    echo "Downloading Solidity $version"
    RELEASE_DETAIL=$(curl -sH "$AUTH_HEADER" "${GH_LINK}${version}")

    if [[ -z "$RELEASE_DETAIL" || $(jq 'has("assets")' <<< "$RELEASE_DETAIL") == "false" ]]; then
      echo "Failed to fetch release details for Solidity $version"
      echo "$RELEASE_DETAIL"
      exit 1
    fi
    BIN_LINK=$(jq -r "$JQ_FILTER" <<< "$RELEASE_DETAIL")

    curl -L \
      -H "Accept: application/octet-stream" \
      -H "$AUTH_HEADER" \
      "${BIN_LINK}" -o "$BIN_PATH"

    # Verify the binary
    chmod +x "$BIN_PATH"
    "solc$use_version" --version
  fi
done

ls -1 /opt/solc-bin/