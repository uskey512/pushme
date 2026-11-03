# shellcheck shell=bash disable=SC2034 # the variables set here are used by the .bats files
# Shared setup for the bats suites. Every test gets its own HOME and XDG
# directories, so the user's real configuration and logs are never touched.

bats_require_minimum_version 1.5.0

PUSHME_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
PUSHME_BIN=$PUSHME_ROOT/bin/pushme
FIXTURES=$PUSHME_ROOT/test/fixtures
# bin/pushme runs under this shell; macOS /bin/bash is the 3.2 it must support.
PUSHME_TEST_BASH=${PUSHME_TEST_BASH:-/bin/bash}

TEST_TOPIC=pushme-test-topic-not-real
TEST_TOKEN=tk_testtokennotreal0000000000000

setup() {
  export HOME=$BATS_TEST_TMPDIR/home
  export XDG_CONFIG_HOME=$HOME/.config
  export XDG_STATE_HOME=$HOME/.local/state
  mkdir -p "$HOME"
  unset PUSHME_CONFIG PUSHME_BACKEND PUSHME_NTFY_URL PUSHME_NTFY_TOPIC \
    PUSHME_NTFY_TOKEN PUSHME_HOSTNAME PUSHME_TIMEOUT PUSHME_NTFY_ATTACH_MAX \
    PUSHME_CLAUDE_MIN_SECONDS PUSHME_CLAUDE_INCLUDE_MESSAGE PUSHME_CLAUDE_INCLUDE_COMMAND \
    PUSHME_CLAUDE_DELAY_SECONDS \
    CLAUDE_PROJECT_DIR PUSHME_PUSHOVER_TOKEN PUSHME_PUSHOVER_USER PUSHME_PUSHOVER_DEVICE \
    PUSHME_CODEX_MIN_SECONDS PUSHME_CODEX_INCLUDE_MESSAGE PUSHME_CODEX_NOTIFY_PERMISSION \
    PUSHME_CODEX_DELAY_SECONDS \
    PUSHME_DND PUSHME_DND_MODE PUSHME_DND_TZ PUSHME_TEST_NOW \
    FAKE_CURL_EXITS FAKE_CURL_STATUS FAKE_CURL_BODY FAKE_CURL_STDERR
  export PUSHME_CURL=$PUSHME_ROOT/test/helpers/fake-curl.sh
  export PUSHME_TEST_RETRY_DELAY=0
  export FAKE_CURL_DIR=$BATS_TEST_TMPDIR/curl
  mkdir -p "$FAKE_CURL_DIR"
  CONFIG_FILE=$XDG_CONFIG_HOME/pushme/config
  ERROR_LOG=$XDG_STATE_HOME/pushme/error.log
}

pushme() {
  "$PUSHME_TEST_BASH" "$PUSHME_BIN" "$@"
}

# Topic and hostname from the environment, for tests that do not care about
# the config file.
use_env_topic() {
  export PUSHME_NTFY_TOPIC=$TEST_TOPIC
  export PUSHME_HOSTNAME=testhost
}

write_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  chmod 700 "$(dirname "$CONFIG_FILE")"
  printf '%s\n' "$@" >"$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

curl_calls() {
  if [ -f "$FAKE_CURL_DIR/calls" ]; then cat "$FAKE_CURL_DIR/calls"; else echo 0; fi
}

# Waits up to 10 seconds for the fake curl to have been called $1 times.
wait_for_calls() {
  local i=0
  while [ "$(curl_calls)" -lt "$1" ]; do
    [ "$i" -lt 100 ] || return 1
    sleep 0.1
    i=$((i + 1))
  done
}

# Path of a file recorded by the latest fake curl call (url, headers, body, args, config).
sent() {
  printf '%s/%s.%s' "$FAKE_CURL_DIR" "$(curl_calls)" "$1"
}

# Value of header $1 in the latest call; fails when the header was not sent.
sent_header() {
  local line
  while IFS= read -r line; do
    case $line in
      "$1: "*)
        printf '%s\n' "${line#"$1: "}"
        return 0
        ;;
    esac
  done <"$(sent headers)"
  return 1
}

# Like sent_header, with an RFC 2047 encoded-word decoded.
sent_header_text() {
  local value
  value=$(sent_header "$1") || return 1
  case $value in
    '=?UTF-8?B?'*'?=')
      value=${value#=?UTF-8?B?}
      printf '%s' "${value%?=}" | base64 --decode
      ;;
    *) printf '%s' "$value" ;;
  esac
}

file_mode() {
  stat -L -c '%a' "$1" 2>/dev/null || stat -L -f '%Lp' "$1"
}

# Repeats string $1 $2 times. Built by doubling: bats runs a DEBUG trap on
# every command of a test, so a loop per character costs seconds.
repeat() {
  local unit=$1 n=$2 out=''
  while [ "$n" -gt 0 ]; do
    if [ $((n % 2)) -eq 1 ]; then out=$out$unit; fi
    unit=$unit$unit
    n=$((n / 2))
  done
  printf '%s' "$out"
}

byte_length() {
  LC_ALL=C wc -c <"$1" | tr -d ' '
}

refute_secret() {
  local text
  for text in "$@"; do
    case $text in
      *"$TEST_TOPIC"* | *"$TEST_TOKEN"*)
        echo "secret leaked: $text" >&2
        return 1
        ;;
    esac
  done
}
