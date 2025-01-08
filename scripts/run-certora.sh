#!/bin/bash

MAX_MSG_LEN=254
SUFFIX_LEN=${#MESSAGE_SUFFIX}
REMAINING_LEN=$((MAX_MSG_LEN - SUFFIX_LEN))
jobs=0

pids=()
configs=()
logs=()

IFS=$'\n' read -rd '' -a confs <<< "$(echo "$CERTORA_CONFIGURATIONS" | sort -u)"

echo "Configurations: ${confs[*]}"

common_prefix="$(echo "$CERTORA_CONFIGURATIONS" | sed -e '1{h;d;}' -e 'G;s,\(.*\).*\n\1.*,\1,;h;$!d' | tr -d '\n')"

current_dir="$(pwd)"

for conf_line in "${confs[@]}"; do

  if [[ ${#conf_line} -gt $MAX_MSG_LEN ]]; then
    MSG_CONF="${conf_line: -$REMAINING_LEN}"
  else
    MSG_CONF="$conf_line"
  fi

  conf_parts=()
  eval "conf_parts=($conf_line)"
  conf_file="${conf_parts[0]}"

  echo "Starting '$conf_line' with message: $MSG_CONF"

  # Create temporal directory for isolated executions
  run_dir="$(mktemp -d)"
  cp -lRP "$current_dir/." "$run_dir/"

  # Create log files
  RAND_SUFF=$(openssl rand -hex 6)
  LOG_FILE="$(printf "%s" "${CERTORA_LOG_DIR}${conf_file#"$common_prefix"}-${RAND_SUFF}.log" | tr -s '/')"
  mkdir -p "$(dirname "$LOG_FILE")"
  logs+=("$LOG_FILE")

  if [[ "$CERTORA_COMPILATION_STEPS_ONLY" == 'true' ]]; then
    conf_parts+=("--compilation_steps_only")
  fi

  cd "$run_dir" || continue

  uvx --from "$CERT_CLI_PACKAGE" certoraRun "${conf_parts[@]}" \
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
    echo "| ${conf#"$common_prefix"} | Failed ($ret) | - | ${logs[i]#$CERTORA_LOG_DIR} |" >> "$CERTORA_REPORT_FILE"
  else
    if [[ "$CERTORA_COMPILATION_STEPS_ONLY" == 'true' ]]; then
        STATUS="Compiled"
    else
        STATUS="Submited"
    fi

    LINK=$(grep -oE "https://(vaas-dev|vaas-stg|prover)\.certora\.com/[^/]+/[0-9]+/[a-zA-Z0-9-]+/?.*\?.*anonymousKey=[a-zA-Z0-9-]+" "${logs[i]}" || true)
    if [[ -z "$LINK" ]]; then
        ((jobs--)) || true
        MD_LINK="-"
    else
        MD_LINK="[link]($LINK)"
    fi

    echo "| ${conf#"$common_prefix"} | $STATUS | $MD_LINK | ${logs[i]#$CERTORA_LOG_DIR} |" >> "$CERTORA_REPORT_FILE"

  fi
done

# Add jobs to output
echo "total_jobs=$jobs" >> "$GITHUB_OUTPUT"
echo "failed_jobs=$failed_jobs" >> "$GITHUB_OUTPUT"

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
