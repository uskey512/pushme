#!/usr/bin/env bash
# Step script of action.yml. Inputs arrive as INPUT_* environment variables
# and are only ever expanded inside quotes, so no input can run as shell code.

set -u

root=$(cd "$(dirname "$0")/.." && pwd)

# Workflow commands read %, CR and LF in their data as escapes.
escape_data() {
  local s=$1
  s=${s//%/%25}
  s=${s//$'\r'/%0D}
  s=${s//$'\n'/%0A}
  REPLY=$s
}

annotate() {
  escape_data "$2"
  printf '::%s title=pushme::%s\n' "$1" "$REPLY"
}

# Multi-line safe; the random delimiter cannot appear in the value by chance
# or by design.
set_output() {
  local delimiter
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  delimiter=pushme_$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  printf '%s<<%s\n%s\n%s\n' "$1" "$delimiter" "$2" "$delimiter" >>"$GITHUB_OUTPUT"
}

parse_bool() {
  case $1 in
    true | True | TRUE) REPLY=1 ;;
    false | False | FALSE | '') REPLY=0 ;;
    *) return 1 ;;
  esac
}

if ! parse_bool "${INPUT_FAIL_ON_ERROR:-}"; then
  annotate error "fail-on-error は true か false にしてください"
  exit 1
fi
fail_on_error=$REPLY

fail() {
  set_output status failed
  if [ "$fail_on_error" = 1 ]; then
    annotate error "通知を送れませんでした: $1"
    exit 1
  fi
  annotate warning "通知を送れませんでした: $1"
  exit 0
}

# Only non-empty inputs override, so PUSHME_* set on the job or a runner's
# config file still apply when an input is left out.
if [ -n "${INPUT_TOPIC:-}" ]; then export PUSHME_NTFY_TOPIC=$INPUT_TOPIC; fi
if [ -n "${INPUT_SERVER:-}" ]; then export PUSHME_NTFY_URL=$INPUT_SERVER; fi
if [ -n "${INPUT_TOKEN:-}" ]; then export PUSHME_NTFY_TOKEN=$INPUT_TOKEN; fi
if [ -n "${INPUT_BACKEND:-}" ]; then export PUSHME_BACKEND=$INPUT_BACKEND; fi
if [ -n "${INPUT_PUSHOVER_TOKEN:-}" ]; then export PUSHME_PUSHOVER_TOKEN=$INPUT_PUSHOVER_TOKEN; fi
if [ -n "${INPUT_PUSHOVER_USER:-}" ]; then export PUSHME_PUSHOVER_USER=$INPUT_PUSHOVER_USER; fi
for secret in "${PUSHME_NTFY_TOPIC:-}" "${PUSHME_NTFY_TOKEN:-}" \
  "${PUSHME_PUSHOVER_TOKEN:-}" "${PUSHME_PUSHOVER_USER:-}"; do
  if [ -n "$secret" ]; then
    escape_data "$secret"
    printf '::add-mask::%s\n' "$REPLY"
  fi
done

args=()
parse_bool "${INPUT_MARKDOWN:-}" || fail "markdown は true か false にしてください"
if [ "$REPLY" = 1 ]; then args+=(--markdown); fi
parse_bool "${INPUT_DRY_RUN:-}" || fail "dry-run は true か false にしてください"
dry_run=$REPLY
if [ "$dry_run" = 1 ]; then args+=(--dry-run); fi
if [ -n "${INPUT_TITLE:-}" ]; then args+=(--title "$INPUT_TITLE"); fi
if [ -n "${INPUT_PRIORITY:-}" ]; then args+=(--priority "$INPUT_PRIORITY"); fi
if [ -n "${INPUT_TAGS:-}" ]; then args+=(--tags "$INPUT_TAGS"); fi
if [ -n "${INPUT_CLICK:-}" ]; then args+=(--click "$INPUT_CLICK"); fi
if [ -n "${INPUT_ATTACH:-}" ]; then args+=(--attach "$INPUT_ATTACH"); fi
args+=(-- "${INPUT_MESSAGE:-}")

errors=$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pushme-action.XXXXXX") || fail "一時ファイルを作れません"
output=$("$root/bin/pushme" send "${args[@]}" 2>"$errors" </dev/null)
status=$?
if [ -n "$output" ]; then printf '%s\n' "$output"; fi
cat "$errors" >&2
detail=$(tail -n 1 "$errors")
rm -f "$errors"

if [ "$status" -ne 0 ]; then
  fail "${detail#pushme: エラー: }"
fi
if [ "$dry_run" = 1 ]; then
  set_output status dry-run
  set_output dry-run-output "$output"
else
  set_output status sent
fi
