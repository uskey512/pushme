#!/usr/bin/env bats

load helpers/common.sh

SESSION=019a1b2c-3d4e-7f80-9a1b-2c3d4e5f6a7b

hook() {
  local fixture=$1
  shift
  run --separate-stderr pushme codex-hook "$@" <"$FIXTURES/codex/$fixture.json"
}

# Runs the hook with a fixture whose fields are changed by the jq filter $2.
hook_with() {
  jq "$2" "$FIXTURES/codex/$1.json" >"$BATS_TEST_TMPDIR/event.json"
  run --separate-stderr pushme codex-hook <"$BATS_TEST_TMPDIR/event.json"
}

state_dir() {
  printf '%s/pushme/codex' "$XDG_STATE_HOME"
}

started_ago() {
  mkdir -p "$(state_dir)"
  echo $(($(date +%s) - $1)) >"$(state_dir)/$SESSION"
}

assert_quiet_success() {
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- UserPromptSubmit and Interrupt -------------------------------------------------

@test "codex-hook: UserPromptSubmit records the start time in its own directory" {
  use_env_topic
  hook user-prompt-submit
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  local recorded now
  recorded=$(cat "$(state_dir)/$SESSION")
  now=$(date +%s)
  [ $((now - recorded)) -ge 0 ]
  [ $((now - recorded)) -le 5 ]
  [ ! -e "$XDG_STATE_HOME/pushme/claude" ]
}

@test "codex-hook: UserPromptSubmit removes records older than 7 days" {
  use_env_topic
  mkdir -p "$(state_dir)"
  touch -t 202001010000 "$(state_dir)/stale-session"
  touch "$(state_dir)/recent-session"
  hook user-prompt-submit
  assert_quiet_success
  [ ! -e "$(state_dir)/stale-session" ]
  [ -e "$(state_dir)/recent-session" ]
}

@test "codex-hook: a subagent's UserPromptSubmit does not restart the clock" {
  use_env_topic
  hook_with user-prompt-submit '.agent_id = "agent-1" | .agent_type = "worker"'
  assert_quiet_success
  [ ! -e "$(state_dir)/$SESSION" ]
}

@test "codex-hook: the session id is reduced to safe characters for the file name" {
  use_env_topic
  hook_with user-prompt-submit '.session_id = "../../evil id"'
  assert_quiet_success
  [ -f "$(state_dir)/evilid" ]
  [ "$(ls -A "$XDG_STATE_HOME/pushme")" = codex ]
}

@test "codex-hook: Interrupt removes the record and sends nothing" {
  use_env_topic
  started_ago 200
  hook interrupt
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ ! -e "$(state_dir)/$SESSION" ]
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
}

# --- Stop -------------------------------------------------------------------------------

@test "codex-hook: Stop after a long turn sends the elapsed time and the reply" {
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
  [[ $(head -n 1 <<<"$body") =~ ^3m2[0-2]s\ ·\ session\ 019a1b2c$ ]] || false
  [ "$(tail -n +2 <<<"$body")" = "$(printf 'テストを直しました。\nすべて通っています。')" ]
  [ ! -e "$(state_dir)/$SESSION" ]
}

@test "codex-hook: the reply is cut to 300 characters, and a null reply leaves one line" {
  use_env_topic
  started_ago 60
  hook_with stop ".last_assistant_message = \"$(repeat あ 400)\""
  assert_quiet_success
  [ "$(tail -n +2 "$(sent body)")" = "$(repeat あ 300)…" ]
  started_ago 60
  hook_with stop '.last_assistant_message = null'
  assert_quiet_success
  [[ $(cat "$(sent body)") =~ ^1m[0-2]s\ ·\ session\ 019a1b2c$ ]] || false
}

@test "codex-hook: PUSHME_CODEX_INCLUDE_MESSAGE=0 leaves the reply out" {
  use_env_topic
  started_ago 60
  PUSHME_CODEX_INCLUDE_MESSAGE=0 hook stop
  assert_quiet_success
  [ "$(wc -l <"$(sent body)" | tr -d ' ')" -eq 0 ]
  [[ $(cat "$(sent body)") == *"· session 019a1b2c" ]] || false
}

@test "codex-hook: a turn shorter than PUSHME_CODEX_MIN_SECONDS is not reported" {
  use_env_topic
  started_ago 10
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ ! -e "$(state_dir)/$SESSION" ]
  started_ago 10
  write_config "PUSHME_CODEX_MIN_SECONDS=5"
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 1 ]
}

@test "codex-hook: Stop without a recorded start sends nothing" {
  use_env_topic
  hook stop
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
}

@test "codex-hook: Stop with stop_hook_active sends nothing and keeps the record" {
  use_env_topic
  started_ago 200
  hook stop-hook-active
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ -f "$(state_dir)/$SESSION" ]
}

@test "codex-hook: a subagent's Stop sends nothing and keeps the record" {
  use_env_topic
  started_ago 200
  hook_with stop '.agent_id = "agent-1"'
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ -f "$(state_dir)/$SESSION" ]
}

# --- PermissionRequest ------------------------------------------------------------------

@test "codex-hook: PermissionRequest reports the tool and its command" {
  use_env_topic
  hook permission-request
  assert_quiet_success
  [ "$(sent_header_text X-Title)" = "my-project 承認待ち" ]
  [ "$(sent_header X-Priority)" = 4 ]
  [ "$(sent_header X-Tags)" = "question,my-project,testhost" ]
  [ "$(cat "$(sent body)")" = "$(printf 'Bash\nrm -rf build && npm test')" ]
}

@test "codex-hook: without a command the description, then the JSON of tool_input is shown" {
  use_env_topic
  hook_with permission-request 'del(.tool_input.command)'
  [ "$(cat "$(sent body)")" = "$(printf 'Bash\nRebuild and run the tests')" ]
  hook_with permission-request '.tool_name = "apply_patch" | .tool_input = {"path": "src/a.js"}'
  [ "$(cat "$(sent body)")" = "$(printf 'apply_patch\n{"path":"src/a.js"}')" ]
  hook_with permission-request '.tool_input.command = ["npm", "test"]'
  [ "$(cat "$(sent body)")" = "$(printf 'Bash\nnpm test')" ]
  assert_quiet_success
}

@test "codex-hook: a long command is cut to 300 characters" {
  use_env_topic
  hook_with permission-request ".tool_input.command = \"$(repeat x 400)\""
  assert_quiet_success
  [ "$(tail -n +2 "$(sent body)")" = "$(repeat x 300)…" ]
}

@test "codex-hook: a subagent's PermissionRequest is reported" {
  use_env_topic
  hook_with permission-request '.agent_id = "agent-1" | .agent_type = "worker"'
  assert_quiet_success
  [ "$(curl_calls)" -eq 1 ]
}

@test "codex-hook: PUSHME_CODEX_NOTIFY_PERMISSION=0 turns PermissionRequest off" {
  use_env_topic
  PUSHME_CODEX_NOTIFY_PERMISSION=0 hook permission-request
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
}

# --- general ----------------------------------------------------------------------------

@test "codex-hook: other events do nothing" {
  use_env_topic
  hook pre-tool-use
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [ ! -e "$(state_dir)" ]
}

@test "codex-hook: the project is the basename of cwd and full paths never appear" {
  use_env_topic
  hook_with permission-request '.cwd = "/home/someone/work/api,v2/"'
  assert_quiet_success
  [ "$(sent_header_text X-Title)" = "api,v2 承認待ち" ]
  [ "$(sent_header X-Tags)" = "question,apiv2,testhost" ]
  started_ago 60
  hook stop
  run ! grep -r -F /home/someone "$FAKE_CURL_DIR"
}

@test "codex-hook: without cwd the project is called Codex" {
  use_env_topic
  hook_with permission-request 'del(.cwd)'
  assert_quiet_success
  [ "$(sent_header X-Tags)" = "question,Codex,testhost" ]
}

@test "codex-hook: always exits 0 with empty stdout, logging what went wrong" {
  use_env_topic
  run --separate-stderr pushme codex-hook <<<"not json"
  assert_quiet_success
  run --separate-stderr pushme codex-hook --bogus </dev/null
  assert_quiet_success
  FAKE_CURL_STATUS=500 hook permission-request
  assert_quiet_success
  PUSHME_NTFY_TOPIC='' hook permission-request
  assert_quiet_success
  PUSHME_CODEX_NOTIFY_PERMISSION=yes hook permission-request
  assert_quiet_success
  local log
  log=$(cat "$ERROR_LOG")
  [[ $log == *"codex-hook: 標準入力が JSON オブジェクトではありません"* ]] || false
  [[ $log == *"--bogus"* ]] || false
  [[ $log == *"HTTP 500"* ]] || false
  [[ $log == *"PUSHME_NTFY_TOPIC"* ]] || false
  [[ $log == *"PUSHME_CODEX_NOTIFY_PERMISSION"* ]] || false
}

@test "codex-hook: without jq it logs the problem and exits 0" {
  use_env_topic
  local bin=$BATS_TEST_TMPDIR/no-jq tool
  mkdir "$bin"
  for tool in cat date mkdir chmod wc tail mv rm; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  run --separate-stderr env PATH="$bin" "$PUSHME_TEST_BASH" "$PUSHME_BIN" codex-hook \
    <"$FIXTURES/codex/permission-request.json"
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [[ $(cat "$ERROR_LOG") == *"codex-hook: jq が見つかりません（Codex の hook には jq が必要です）"* ]] || false
}

@test "codex-hook: --dry-run prints to stderr and sends nothing" {
  use_env_topic
  hook permission-request --dry-run
  assert_quiet_success
  [ "$(curl_calls)" -eq 0 ]
  [[ $stderr == *"X-Title: my-project 承認待ち"* ]] || false
}

@test "codex-hook: invalid Codex settings do not break send, and doctor reports them" {
  use_env_topic
  export PUSHME_CODEX_MIN_SECONDS=soon
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  run -1 pushme doctor </dev/null
  [[ $output == *"[NG] PUSHME_CODEX_MIN_SECONDS"* ]] || false
}
