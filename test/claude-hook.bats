#!/usr/bin/env bats

load helpers/common.sh

SESSION=abc12345-6789-4def-8123-456789abcdef

# fd 3 is closed because bats waits for every process holding it, and a
# held-back notification's process outlives the hook.
hook() {
  local fixture=$1
  shift
  run --separate-stderr pushme claude-hook "$@" <"$FIXTURES/claude/$fixture.json" 3>&-
}

# Runs the hook with a fixture whose fields are changed by the jq filter $2.
hook_with() {
  jq "$2" "$FIXTURES/claude/$1.json" >"$BATS_TEST_TMPDIR/event.json"
  run --separate-stderr pushme claude-hook <"$BATS_TEST_TMPDIR/event.json" 3>&-
}

state_dir() {
  printf '%s/pushme/claude' "$XDG_STATE_HOME"
}

# Number of notifications of kind $1 held back for the session.
held() {
  local file n=0
  for file in "$(state_dir)/$SESSION.$1".*; do
    [ -f "$file" ] && n=$((n + 1))
  done
  echo "$n"
}

started_ago() {
  mkdir -p "$(state_dir)"
  echo $(($(date +%s) - $1)) >"$(state_dir)/$SESSION"
}

assert_quiet_success() {
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- UserPromptSubmit --------------------------------------------------------------

@test "claude-hook: UserPromptSubmit records the start time and sends nothing" {
  use_env_topic
  hook user-prompt-submit
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  local recorded now
  recorded=$(cat "$(state_dir)/$SESSION")
  now=$(date +%s)
  [ $((now - recorded)) -ge 0 ] && [ $((now - recorded)) -le 5 ]
}

@test "claude-hook: UserPromptSubmit removes records older than 7 days" {
  use_env_topic
  mkdir -p "$(state_dir)"
  touch -t 202001010000 "$(state_dir)/stale-session"
  touch "$(state_dir)/recent-session"
  hook user-prompt-submit
  assert_quiet_success
  [ ! -e "$(state_dir)/stale-session" ]
  [ -e "$(state_dir)/recent-session" ]
}

@test "claude-hook: the session id is reduced to safe characters for the file name" {
  use_env_topic
  hook_with user-prompt-submit '.session_id = "../../evil id"'
  assert_quiet_success
  [ -f "$(state_dir)/evilid" ]
  [ "$(ls -A "$XDG_STATE_HOME/pushme")" = claude ]
}

# --- Stop ----------------------------------------------------------------------------

@test "claude-hook: Stop after a long turn sends the elapsed time and the reply" {
  use_env_topic
  started_ago 200
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 1 ]
  [ "$(sent_header_text X-Title)" = "my-project 完了" ]
  [ "$(sent_header X-Priority)" = 4 ]
  [ "$(sent_header X-Tags)" = "white_check_mark,my-project,testhost" ]
  local body
  body=$(cat "$(sent body)")
  [[ $(head -n 1 <<<"$body") =~ ^3m2[0-2]s\ ·\ session\ abc12345$ ]]
  [ "$(tail -n +2 <<<"$body")" = "$(printf 'テストを直しました。\nすべて通っています。')" ]
  [ ! -e "$(state_dir)/$SESSION" ]
}

@test "claude-hook: the reply is cut to its first 300 characters" {
  use_env_topic
  started_ago 60
  hook_with stop ".last_assistant_message = \"$(repeat あ 400)\""
  assert_quiet_success
  [ "$(tail -n +2 "$(sent body)")" = "$(repeat あ 300)…" ]
}

@test "claude-hook: PUSHME_CLAUDE_INCLUDE_MESSAGE=0 leaves the reply out" {
  use_env_topic
  started_ago 60
  PUSHME_CLAUDE_INCLUDE_MESSAGE=0 hook stop
  assert_quiet_success
  [ "$(wc -l <"$(sent body)" | tr -d ' ')" -eq 0 ]
  [[ $(cat "$(sent body)") == *"· session abc12345" ]]
}

@test "claude-hook: a turn shorter than PUSHME_CLAUDE_MIN_SECONDS is not reported" {
  use_env_topic
  started_ago 10
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ ! -e "$(state_dir)/$SESSION" ]
  started_ago 10
  write_config "PUSHME_CLAUDE_MIN_SECONDS=5"
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 1 ]
}

@test "claude-hook: Stop without a recorded start sends nothing" {
  use_env_topic
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
}

@test "claude-hook: Stop with stop_hook_active sends nothing and keeps the record" {
  use_env_topic
  started_ago 200
  hook stop-hook-active
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ -f "$(state_dir)/$SESSION" ]
}

@test "claude-hook: events from a subagent neither report nor touch the record" {
  use_env_topic
  started_ago 200
  hook stop-subagent
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ -f "$(state_dir)/$SESSION" ]
  rm "$(state_dir)/$SESSION"
  hook_with user-prompt-submit '.agent_id = "agent-def456"'
  assert_quiet_success
  [ ! -e "$(state_dir)/$SESSION" ]
}

# --- Notification and StopFailure ---------------------------------------------------

@test "claude-hook: a permission prompt is reported with its title and message" {
  use_env_topic
  hook notification-permission
  assert_quiet_success
  [ "$(sent_header_text X-Title)" = "my-project 承認待ち" ]
  [ "$(sent_header X-Priority)" = 4 ]
  [ "$(sent_header X-Tags)" = "question,my-project,testhost" ]
  [ "$(cat "$(sent body)")" = "$(printf 'Permission needed\nClaude needs your permission to use Bash')" ]
}

@test "claude-hook: elicitation dialogs are reported too" {
  use_env_topic
  local type
  for type in elicitation_dialog elicitation_url_dialog; do
    hook_with notification-permission ".notification_type = \"$type\""
    assert_quiet_success
  done
  [ "$(curl_calls)" -eq 2 ]
}

@test "claude-hook: other notification types are ignored" {
  use_env_topic
  hook notification-idle
  assert_quiet_success
  hook_with notification-permission 'del(.notification_type)'
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
}

@test "claude-hook: StopFailure reports the error, its details and the API message" {
  use_env_topic
  hook stop-failure
  assert_quiet_success
  [ "$(sent_header_text X-Title)" = "my-project エラー" ]
  [ "$(sent_header X-Priority)" = 4 ]
  [ "$(sent_header X-Tags)" = "x,my-project,testhost" ]
  [ "$(cat "$(sent body)")" = "$(printf 'rate_limit\n429 Too Many Requests\nAPI Error: Rate limit reached')" ]
}

@test "claude-hook: other events do nothing" {
  use_env_topic
  hook pre-tool-use
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ ! -e "$(state_dir)" ]
}

# --- held back (PUSHME_CLAUDE_DELAY_SECONDS) ----------------------------------------------

@test "claude-hook: with a delay, an unanswered permission prompt is reported afterwards" {
  use_env_topic
  export PUSHME_CLAUDE_DELAY_SECONDS=1
  hook notification-permission
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ "$(held ask)" -eq 1 ]
  wait_for_calls 1
  [ "$(sent_header_text X-Title)" = "my-project 承認待ち" ]
  [ "$(cat "$(sent body)")" = "$(printf 'Permission needed\nClaude needs your permission to use Bash')" ]
  [ "$(held ask)" -eq 0 ]
}

@test "claude-hook: with a delay, a finished turn is not reported once the user writes again" {
  use_env_topic
  export PUSHME_CLAUDE_DELAY_SECONDS=1
  started_ago 60
  hook stop
  assert_quiet_success
  [ "$(held finished)" -eq 1 ]
  hook user-prompt-submit
  assert_quiet_success
  [ "$(held finished)" -eq 0 ]
  sleep 2
  [ "$(curl_calls)" -eq 0 ]
}

@test "claude-hook: a finished turn is reported after the delay with its elapsed time" {
  use_env_topic
  write_config "PUSHME_CLAUDE_DELAY_SECONDS=1"
  started_ago 200
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  wait_for_calls 1
  [ "$(sent_header_text X-Title)" = "my-project 完了" ]
  [[ $(head -n 1 "$(sent body)") =~ ^3m2[0-2]s\ ·\ session\ abc12345$ ]]
}

@test "claude-hook: only the asking agent's next tool call cancels its prompt" {
  use_env_topic
  export PUSHME_CLAUDE_DELAY_SECONDS=100
  hook_with permission-request '.agent_id = "agent-def456"'
  assert_quiet_success
  hook notification-permission
  [ "$(held ask)" -eq 1 ]
  hook post-tool-use
  [ "$(held ask)" -eq 1 ]
  hook_with post-tool-use '.agent_id = "other-agent"'
  [ "$(held ask)" -eq 1 ]
  hook_with post-tool-use '.agent_id = "agent-def456" | .hook_event_name = "PostToolUseFailure"'
  assert_quiet_success
  [ "$(held ask)" -eq 0 ]
  [ ! -e "$(state_dir)/$SESSION.asker" ]
}

@test "claude-hook: without a PermissionRequest the prompt is the main conversation's" {
  use_env_topic
  export PUSHME_CLAUDE_DELAY_SECONDS=100
  hook notification-permission
  hook_with post-tool-use '.agent_id = "agent-def456"'
  [ "$(held ask)" -eq 1 ]
  hook post-tool-use
  [ "$(held ask)" -eq 0 ]
}

@test "claude-hook: Stop and StopFailure cancel the main conversation's prompt" {
  use_env_topic
  export PUSHME_CLAUDE_DELAY_SECONDS=100
  hook notification-permission
  hook stop
  [ "$(held ask)" -eq 0 ]
  hook notification-permission
  hook stop-failure
  [ "$(held ask)" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
  [ "$(sent_header_text X-Title)" = "my-project エラー" ]
  hook_with permission-request '.agent_id = "agent-def456"'
  hook notification-permission
  hook stop
  [ "$(held ask)" -eq 1 ]
}

@test "claude-hook: UserPromptSubmit and SessionEnd cancel everything held back" {
  use_env_topic
  export PUSHME_CLAUDE_DELAY_SECONDS=100
  local event
  for event in user-prompt-submit session-end; do
    started_ago 60
    hook stop
    hook_with permission-request '.agent_id = "agent-def456"'
    hook notification-permission
    [ "$(held finished)" -eq 1 ] && [ "$(held ask)" -eq 1 ]
    hook "$event"
    assert_quiet_success
    [ "$(held finished)" -eq 0 ] && [ "$(held ask)" -eq 0 ]
  done
  [ "$(curl_calls)" -eq 0 ]
}

@test "claude-hook: a newer prompt replaces the one held back" {
  use_env_topic
  export PUSHME_CLAUDE_DELAY_SECONDS=1
  hook notification-permission
  hook_with notification-permission '.notification_type = "elicitation_dialog" | .message = "Pick a branch"'
  [ "$(held ask)" -eq 1 ]
  wait_for_calls 1
  sleep 1
  [ "$(curl_calls)" -eq 1 ]
  [ "$(cat "$(sent body)")" = "$(printf 'Permission needed\nPick a branch')" ]
}

@test "claude-hook: tool calls with nothing held back leave no trace" {
  use_env_topic
  hook post-tool-use
  assert_quiet_success
  [ ! -e "$(state_dir)" ]
}

@test "claude-hook: --dry-run with a delay says when it would send" {
  use_env_topic
  PUSHME_CLAUDE_DELAY_SECONDS=300 hook notification-permission --dry-run
  assert_quiet_success
  [[ $stderr == *"300 秒後、それまでに応答がなければ送ります"* ]]
  [[ $stderr == *"X-Title: my-project 承認待ち"* ]]
  [ "$(curl_calls)" -eq 0 ]
}

@test "claude-hook: an invalid PUSHME_CLAUDE_DELAY_SECONDS is logged and reported by doctor" {
  use_env_topic
  export PUSHME_CLAUDE_DELAY_SECONDS=5m
  hook notification-permission
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [[ $(cat "$ERROR_LOG") == *"PUSHME_CLAUDE_DELAY_SECONDS"* ]]
  run -1 pushme doctor </dev/null
  [[ $output == *"[NG] PUSHME_CLAUDE_DELAY_SECONDS"* ]]
}

# --- project name ---------------------------------------------------------------------

@test "claude-hook: CLAUDE_PROJECT_DIR names the project, commas are dropped from the tag" {
  use_env_topic
  CLAUDE_PROJECT_DIR=/home/someone/work/api,v2/ hook notification-permission
  assert_quiet_success
  [ "$(sent_header_text X-Title)" = "api,v2 承認待ち" ]
  [ "$(sent_header X-Tags)" = "question,apiv2,testhost" ]
}

@test "claude-hook: full paths never appear in the notification" {
  use_env_topic
  started_ago 60
  hook stop
  hook stop-failure
  hook notification-permission
  [ "$(curl_calls)" -eq 3 ]
  run ! grep -r -F /home/someone "$FAKE_CURL_DIR"
}

# --- never in Claude Code's way ---------------------------------------------------------

@test "claude-hook: always exits 0 with empty stdout, logging what went wrong" {
  use_env_topic
  run --separate-stderr pushme claude-hook <<<"not json"
  assert_quiet_success
  run --separate-stderr pushme claude-hook --bogus </dev/null
  assert_quiet_success
  FAKE_CURL_STATUS=500 hook stop-failure
  assert_quiet_success
  PUSHME_NTFY_TOPIC='' hook stop-failure
  assert_quiet_success
  started_ago 60
  PUSHME_CLAUDE_MIN_SECONDS=soon hook stop
  assert_quiet_success
  local log
  log=$(cat "$ERROR_LOG")
  [[ $log == *"JSON オブジェクトではありません"* ]]
  [[ $log == *"--bogus"* ]]
  [[ $log == *"HTTP 500"* ]]
  [[ $log == *"PUSHME_NTFY_TOPIC"* ]]
  [[ $log == *"PUSHME_CLAUDE_MIN_SECONDS"* ]]
}

@test "claude-hook: without jq it logs the problem and exits 0" {
  use_env_topic
  local bin=$BATS_TEST_TMPDIR/no-jq tool
  mkdir "$bin"
  for tool in cat date mkdir chmod wc tail mv rm; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  run --separate-stderr env PATH="$bin" "$PUSHME_TEST_BASH" "$PUSHME_BIN" claude-hook \
    <"$FIXTURES/claude/stop-failure.json"
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [[ $(cat "$ERROR_LOG") == *"jq が見つかりません"* ]]
}

@test "claude-hook: the hook returns before the send, which outlives the hook's process group" {
  use_env_topic
  unset PUSHME_TEST_WAIT_SEND
  export FAKE_CURL_SLEEP=1
  started_ago 60
  # As claude -p does to a hook still running when it exits, the hook's
  # process group is killed.
  local pid
  set -m
  pushme claude-hook <"$FIXTURES/claude/stop.json" >/dev/null 3>&- &
  pid=$!
  set +m
  wait "$pid"
  kill -TERM -- "-$pid" 2>/dev/null || true
  [ "$(curl_calls)" -eq 0 ]
  wait_for_calls 1
  [ "$(sent_header_text X-Title)" = "my-project 完了" ]
}

@test "claude-hook: --dry-run prints to stderr and sends nothing" {
  use_env_topic
  hook stop-failure --dry-run
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [[ $stderr == *"X-Title: my-project エラー"* ]]
}

@test "claude-hook: invalid Claude settings do not break send, and doctor reports them" {
  use_env_topic
  export PUSHME_CLAUDE_MIN_SECONDS=soon PUSHME_CLAUDE_INCLUDE_MESSAGE=yes
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  run -1 pushme doctor </dev/null
  [[ $output == *"[NG] PUSHME_CLAUDE_MIN_SECONDS"* ]]
}
