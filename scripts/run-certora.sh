#!/bin/bash

if [ "$DEBUG_LEVEL" -gt 0 ]; then
  set -x
fi

MAX_MSG_LEN=254
SUFFIX_LEN=${#MESSAGE_SUFFIX}
REMAINING_LEN=$((MAX_MSG_LEN - SUFFIX_LEN))
jobs=0

pids=()
configs=()
logs=()

# Remove leading spaces, trailing spaces, comments, and empty lines
CERTORA_CONFIGURATIONS="$(sed -r 's/^\s+//; s/\s+$//; /^[[:blank:]]*#/d; s/^#.*//; /^\s*$/d' <<<"$CERTORA_CONFIGURATIONS")"

IFS=$'\n' read -rd '' -a confs <<<"$(echo "$CERTORA_CONFIGURATIONS" | sort -u)"

echo "Configurations: ${confs[*]}"

if [[ ${#confs[@]} -gt 1 ]]; then
  # Extract the common prefix from the configurations
  # Sed script to extract the common prefix
  # For the first line, copy pattern space to hold space and delete the pattern space
  # Append a newline and the hold space to the pattern space, capture the common prefix
  # Copy the pattern space to the hold space and delete the pattern space until the last line
  common_prefix="$(echo "$CERTORA_CONFIGURATIONS" | sed -e '1{h;d;}' -e 'G;s,\(.*\).*\n\1.*,\1,;s,\(.*[/ ]\).*$,\1,;h;$!d' | tr -d '\n')"
elif [[ "${confs[0]}" == */* ]]; then
  # Keep the file name only
  common_prefix="$(echo "${confs[0]}" | sed 's/\(.*\/\)[^\/]*$/\1/')"
fi

# Choose the right entrypoint for the ecosystem
if [[ "$CERTORA_ECOSYSTEM" == "evm" ]]; then
  CLI_ENTRYPOINT="certoraRun"
elif [[ "$CERTORA_ECOSYSTEM" == "solana" ]]; then
  CLI_ENTRYPOINT="certoraSolanaProver"
else
  echo "::error title=Unsupported Ecosystem::Ecosystem $CERTORA_ECOSYSTEM is not supported. Please use 'evm' or 'solana'."
  exit 1
fi
echo "Using cli entrypoint: $CLI_ENTRYPOINT"

current_dir="$(pwd)"

# Create all folders and copy/link all files before any certoraRun executions
# in case we need to modify them
for conf_line in "${confs[@]}"; do
  # Create a temporal directory for isolated executions
  # Use an MD5 hash of the configuration file as the directory name
  conf_hash=$(echo -n "$conf_line" | md5sum | awk '{print $1}')
  run_dir="/tmp/${conf_hash}"
  mkdir -p "$run_dir"

  if [[ "$CERTORA_USE_HARD_LINKS" == "true" ]]; then
    echo "Creating folder and hardlinks for: $conf_line ($run_dir)"
    cp -lRP --update=none "$GITHUB_WORKSPACE/." "$run_dir/"
  else
    echo "Creating folder and copying files for: $conf_line ($run_dir)"
    cp -R --update=none "$GITHUB_WORKSPACE/." "$run_dir/"
  fi
done

for conf_line in "${confs[@]}"; do

  short_conf_line="${conf_line#"$common_prefix"}"
  if [[ ${#short_conf_line} -gt $MAX_MSG_LEN ]]; then
    MSG_CONF="${short_conf_line: -$REMAINING_LEN}"
  else
    MSG_CONF="$short_conf_line"
  fi

  conf_parts=()
  eval "conf_parts=($conf_line)"
  conf_file="${conf_parts[0]}"

  if [[ "$CERTORA_COMPILATION_STEPS_ONLY" == 'true' ]]; then
    ACTION="Compiling"
  else
    ACTION="Submitting"
  fi

  echo "$ACTION '$conf_line' with message: $MSG_CONF"
  conf_hash=$(echo -n "$conf_line" | md5sum | awk '{print $1}')
  run_dir="/tmp/${conf_hash}"

  # If we're using github.working-directory we have changed the run directory relative
  # to the workspace
  if [[ "$current_dir" != "$GITHUB_WORKSPACE" ]]; then
    run_dir="$run_dir/$(realpath --relative-to="$GITHUB_WORKSPACE" "$current_dir")"
  fi

  # Create log files
  RAND_SUFF=$(openssl rand -hex 6)
  LOG_FILE="$(printf "%s" "${CERTORA_LOG_DIR}${conf_file}-${RAND_SUFF}.log" | tr -s '/')"
  mkdir -p "$(dirname "$LOG_FILE")"
  logs+=("$LOG_FILE")

  if [[ "$CERTORA_COMPILATION_STEPS_ONLY" == 'true' ]]; then
    conf_parts+=("--compilation_steps_only")
  fi

  if [ "$DEBUG_LEVEL" -gt 1 ]; then
    conf_parts+=("--debug")
  fi

  cd "$run_dir" || continue

  if [ "$DEBUG_LEVEL" -gt 2 ]; then
    find . -path './.git' -prune -o -exec stat -c'%U %G %a %n' {} \;
  fi

  uvx --from "$CERT_CLI_PACKAGE" "$CLI_ENTRYPOINT" "${conf_parts[@]}" \
    --msg "${MSG_CONF} ${MESSAGE_SUFFIX}" \
    --server "$CERTORA_SERVER" \
    --group_id "$GROUP_ID" \
    --wait_for_results none \
    >"$LOG_FILE" 2>&1 &

  pids+=($!)
  configs+=("$conf_line")

  ((jobs++)) || true

  cd "$current_dir" || exit 1
done

cat >"$CERTORA_REPORT_FILE" <<EOF
## Certora Run Started ($CERTORA_JOB_NAME)

- Group ID: $GROUP_ID

| Config | Status | Link | Log File |
|--------|--------|------|----------|
EOF

# Wait for all jobs to finish and mark if any failed
failed_jobs=0
for i in "${!pids[@]}"; do
  ret=0
  wait "${pids[i]}" || ret=$?
  conf="${configs[i]}"
  if [[ $ret -ne 0 ]]; then
    ((jobs--)) || true
    ((failed_jobs++)) || true
    echo "| ${conf#"$common_prefix"} | Failed ($ret) | - | ${logs[i]#$CERTORA_LOG_DIR} |" >>"$CERTORA_REPORT_FILE"
  else
    if [[ "$CERTORA_COMPILATION_STEPS_ONLY" == 'true' ]]; then
      STATUS="Compiled"
    else
      STATUS="Submitted"
    fi

    LINK=$(grep -oE "https://(vaas-dev|vaas-stg|prover)\.certora\.com/[^/]+/[0-9]+/[a-zA-Z0-9-]+/?.*\?.*anonymousKey=[a-zA-Z0-9-]+" "${logs[i]}" || true)
    if [[ -z "$LINK" ]]; then
      ((jobs--)) || true
      MD_LINK="-"
    else
      MD_LINK="[link]($LINK)"
    fi

    echo "| ${conf#"$common_prefix"} | $STATUS | $MD_LINK | ${logs[i]#$CERTORA_LOG_DIR} |" >>"$CERTORA_REPORT_FILE"

  fi
done

# Add jobs to output
echo "total_jobs=$jobs" >>"$GITHUB_OUTPUT"
echo "failed_jobs=$failed_jobs" >>"$GITHUB_OUTPUT"

# Remove empty log files
find "$CERTORA_LOG_DIR" -type f -empty -delete

cat >>"$CERTORA_REPORT_FILE" <<EOF

### Certora Run Summary

- Started $jobs jobs
- $failed_jobs jobs failed

EOF

if [[ $failed_jobs -ne 0 ]]; then
  echo "Some configurations failed! Please check the logs."
  exit 1
fi
