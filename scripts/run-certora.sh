#!/bin/bash

if [ "$DEBUG_LEVEL" -gt 0 ]; then
  set -x
fi

MAX_MSG_LEN=254
SUFFIX_LEN=${#MESSAGE_SUFFIX}
REMAINING_LEN=$((MAX_MSG_LEN - SUFFIX_LEN))
jobs=0

pids=()
rets=()
configs=()
logs=()


# Read configurations from file specified by $CERTORA_CONFIGURATIONS_FILE
if [[ -z "$CERTORA_CONFIGURATIONS_FILE" ]]; then
  echo "::error title=Missing Configurations File::CERTORA_CONFIGURATIONS_FILE is not set."
  exit 1
fi

IFS=$'\n' read -rd '' -a confs < "$CERTORA_CONFIGURATIONS_FILE"

echo "Configurations: ${confs[*]}"

if [[ ${#confs[@]} -gt 1 ]]; then
  # Extract the common prefix from the configurations
  # Use the contents of the file for prefix extraction
  common_prefix="$(sed -e '1{h;d;}' -e 'G;s,\(.*\).*\n\1.*,\1,;s,\(.*[/ ]\).*$,\1,;h;$!d' "$CERTORA_CONFIGURATIONS_FILE" | tr -d '\n')"
elif [[ "${confs[0]}" == */* ]]; then
  # Keep the file name only
  common_prefix="$(echo "${confs[0]}" | sed 's/\(.*\/\)[^\/]*$/\1/')"
fi

# Choose the right entrypoint for the ecosystem
if [[ "$CERTORA_ECOSYSTEM" == "evm" ]]; then
  CLI_ENTRYPOINT="certoraRun"
elif [[ "$CERTORA_ECOSYSTEM" == "solana" ]]; then
  CLI_ENTRYPOINT="certoraSolanaProver"
elif [[ "$CERTORA_ECOSYSTEM" == "sui" ]]; then
  CLI_ENTRYPOINT="certoraSuiProver"
elif [[ "$CERTORA_ECOSYSTEM" == "soroban" ]]; then
  CLI_ENTRYPOINT="certoraSorobanProver"
else
  echo "::error title=Unsupported Ecosystem::Ecosystem $CERTORA_ECOSYSTEM is not supported. Please use 'evm', 'solana', 'sui', or 'soroban'."
  exit 1
fi
echo "Using cli entrypoint: $CLI_ENTRYPOINT"
uvx --from "$CERT_CLI_PACKAGE" "$CLI_ENTRYPOINT" --version

current_dir="$(pwd)"

# Sharing one working directory across concurrent runs lets them race on shared
# build artifacts (e.g. a common cargo target/ directory).
if [[ "$CERTORA_USE_WORKSPACE_DIR" == "true" && "$CERTORA_RUN_SERIALLY" != "true" ]]; then
  echo "::warning title=Possible race conditions::use-workspace-dir is true but run-serially is false: configurations run concurrently in a shared working directory and may race on shared build artifacts. Consider setting run-serially to true."
fi

# Create all folders and copy/link all files before any certoraRun executions
# in case we need to modify them
if [[ "$CERTORA_USE_WORKSPACE_DIR" != "true" ]]; then
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
fi

for conf_line in "${confs[@]}"; do

  short_conf_line="${conf_line#"$common_prefix"}"
  if [[ ${#short_conf_line} -gt $MAX_MSG_LEN ]]; then
    MSG_CONF="${short_conf_line: -$REMAINING_LEN}"
  else
    MSG_CONF="$short_conf_line"
  fi

  conf_parts=()
  conf_tmp="$(mktemp)"  # TMP file so we can check exit status of xargs
  # Split into words honoring quotes
  if ! printf '%s' "$conf_line" | xargs -r printf '%s\0' > "$conf_tmp"; then
    # xargs exits non-zero on unbalanced quotes
    echo "::error title=Invalid Configuration::Could not parse configuration line (check for unbalanced quotes): $conf_line"
    rm -f "$conf_tmp"
    exit 1
  fi
  mapfile -t -d '' conf_parts < "$conf_tmp"  # read NUL-delimited words into the array
  rm -f "$conf_tmp"
  conf_file="${conf_parts[0]}"

  if [[ "$CERTORA_COMPILATION_STEPS_ONLY" == 'true' ]]; then
    ACTION="Compiling"
  else
    ACTION="Submitting"
  fi

  echo "$ACTION '$conf_line' with message: $MSG_CONF"

  if [[ "$CERTORA_USE_WORKSPACE_DIR" == "true" ]]; then
    run_dir="$current_dir"
  else
    conf_hash=$(echo -n "$conf_line" | md5sum | awk '{print $1}')
    run_dir="/tmp/${conf_hash}"

    # If we're using github.working-directory we have changed the run directory relative
    # to the workspace
    if [[ "$current_dir" != "$GITHUB_WORKSPACE" ]]; then
      run_dir="$run_dir/$(realpath --relative-to="$GITHUB_WORKSPACE" "$current_dir")"
    fi
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
  pid=$!

  if [[ "$CERTORA_RUN_SERIALLY" == "true" ]]; then
    # Wait for this job before launching the next.
    ret=0
    wait "$pid" || ret=$?
    rets+=("$ret")
  else
    pids+=("$pid")
  fi
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
for i in "${!configs[@]}"; do
  if [[ "$CERTORA_RUN_SERIALLY" == "true" ]]; then
    ret="${rets[i]}"
  else
    ret=0
    wait "${pids[i]}" || ret=$?
  fi
  conf="${configs[i]}"
  if [[ $ret -ne 0 ]]; then
    ((jobs--)) || true
    ((failed_jobs++)) || true
    echo "| ${conf#"$common_prefix"} | Failed ($ret) | - | ${logs[i]#$CERTORA_LOG_DIR} |" >>"$CERTORA_REPORT_FILE"
  else
    if [[ "$CERTORA_COMPILATION_STEPS_ONLY" == 'true' ]]; then
      STATUS="Compiled"
      MD_LINK="-"
    else
      STATUS="Submitted"
      LINK=$(grep -oE "https://(vaas-dev|vaas-stg|prover)\.certora\.com/[^/]+/[0-9]+/[a-zA-Z0-9-]+/?.*\?.*anonymousKey=[a-zA-Z0-9-]+" "${logs[i]}" || true)
      if [[ -z "$LINK" ]]; then
        ((jobs--)) || true
        MD_LINK="-"
      else
        MD_LINK="[link]($LINK)"
      fi
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
