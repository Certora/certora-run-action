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
rets=()


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

# Build signature for a Solana conf.
#
# Solana compilation is expensive but depends only on the program source
# (shared) and the Cargo features selected by the conf's `features` property.
# So we group confs by their feature set: confs that produce the same binary
# share a signature.
solana_build_sig() {
  local conf_file="$1"
  # extract the features list, line-by-line:
  # 1. drop full line comments
  # 2. flatten newlines as whitespaces
  # 3. find all "cargo_features" properties
  # 4. find all double-quoted entries (i.e. the feature flags + "cargo_features" itself)
  # 5. drop "cargo_features" from the list (the key)
  # 6. sort and dedup
  # 7. join into comma-separated list
  # If there is no "features" key, this gives the empty string
  local feats
  feats="$(
    grep -vE '^[[:space:]]*//' "$conf_file" 2>/dev/null |
    tr '\n' ' ' |
    grep -oE '"cargo_features"[[:space:]]*:[[:space:]]*\[[^]]*\]' |
    grep -oE '"[^"]*"' |
    grep -vxF '"cargo_features"' |
    sort -u |
    tr '\n' ','
  )"
  echo -n "$feats" | md5sum | awk '{print $1}'
}

# Pick the working directory for a configuration.
#
# All Solana confs share one working directory, so the dependencies are compiled
# once and Cargo's `target/` (which caches artifacts per feature set) is reused
# across every feature set. Different feature sets must not build at the same
# time, since they all write the same `target/.../<program>.so`; the run loop
# serializes feature sets to avoid that race. Other ecosystems keep an isolated
# directory per conf, since different confs may modify files or pass
# conf-specific build arguments.
get_run_dir() {
  local conf_line="$1"
  if [[ "$CERTORA_ECOSYSTEM" == "solana" ]]; then
    printf '/tmp/certora-shared-%s' "$GROUP_ID"
  else
    printf '/tmp/%s' "$(echo -n "$conf_line" | md5sum | awk '{print $1}')"
  fi
}

# For Solana, order confs so those sharing a feature set are adjacent. The run
# loop then builds one feature-set batch to completion before the next. Confs in
# a batch (identical cargo_features) build the same binary, so they are safe to
# run in parallel; different batches are not, as they share one Cargo target.
if [[ "$CERTORA_ECOSYSTEM" == "solana" ]]; then
  ordered_confs=()
  while IFS= read -r ordered_line; do
    ordered_confs+=("${ordered_line#*$'\t'}")
  done < <(
    for conf_line in "${confs[@]}"; do
      eval "sig_parts=($conf_line)"
      printf '%s\t%s\n' "$(solana_build_sig "${sig_parts[0]}")" "$conf_line"
    done | sort
  )
  confs=("${ordered_confs[@]}")
fi

# Wait for every launched background job not yet waited on, recording each exit
# code in rets[] (indexed like pids[]). Used both as a barrier between Solana
# feature-set batches and to collect results for the report.
drain_pids() {
  local k r
  for (( k=${#rets[@]}; k<${#pids[@]}; k++ )); do
    r=0
    wait "${pids[k]}" || r=$?
    rets[k]=$r
  done
}

# Create all folders and copy/link all files before any certoraRun executions
# in case we need to modify them
prepared_dirs=""
for conf_line in "${confs[@]}"; do
  run_dir="$(get_run_dir "$conf_line")"

  # Only copy into each directory once (Solana confs with the same features
  # resolve to the same directory). run_dir is a /tmp path with no ':' so a
  # colon-delimited set is safe here.
  case ":$prepared_dirs:" in
    *":$run_dir:"*) continue ;;
  esac
  prepared_dirs="$prepared_dirs:$run_dir"

  mkdir -p "$run_dir"

  if [[ "$CERTORA_USE_HARD_LINKS" == "true" ]]; then
    echo "Creating folder and hardlinks for: $conf_line ($run_dir)"
    cp -lRP --update=none "$GITHUB_WORKSPACE/." "$run_dir/"
  else
    echo "Creating folder and copying files for: $conf_line ($run_dir)"
    cp -R --update=none "$GITHUB_WORKSPACE/." "$run_dir/"
  fi
done

prev_sig=""
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

  # Drain the previous Solana feature-set batch before building a different one
  # (all Solana confs share one Cargo target / one program.so output).
  if [[ "$CERTORA_ECOSYSTEM" == "solana" ]]; then
    cur_sig="$(solana_build_sig "$conf_file")"
    if [[ -n "$prev_sig" && "$cur_sig" != "$prev_sig" ]]; then
      drain_pids
    fi
    prev_sig="$cur_sig"
  fi

  if [[ "$CERTORA_COMPILATION_STEPS_ONLY" == 'true' ]]; then
    ACTION="Compiling"
  else
    ACTION="Submitting"
  fi

  echo "$ACTION '$conf_line' with message: $MSG_CONF"
  run_dir="$(get_run_dir "$conf_line")"

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

# Drain the final batch, then mark any failed jobs in the report
drain_pids
failed_jobs=0
for i in "${!pids[@]}"; do
  ret=${rets[i]}
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
