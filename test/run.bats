#!/usr/bin/env bats

load helpers/common.sh

# --- exit codes and default message -------------------------------------------

@test "run: success is reported with the default title, priority and tags" {
  use_env_topic
  run pushme run -- true </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
  [ "$(sent_header_text X-Title)" = "true 成功" ]
  [ "$(sent_header X-Priority)" = 4 ]
  [ "$(sent_header X-Tags)" = "white_check_mark,testhost" ]
  local body
  body=$(cat "$(sent body)")
  [[ $body == *'$ true'* ]]
  [[ $body == *"終了コード: 0"* ]]
  [[ $body =~ 所要時間:\ [0-9]+s ]]
}

@test "run: a failing command's exit code is passed through and reported" {
  use_env_topic
  run pushme run -- sh -c 'exit 3' </dev/null
  [ "$status" -eq 3 ]
  [ "$(sent_header_text X-Title)" = "sh 失敗 (exit 3)" ]
  [ "$(sent_header X-Priority)" = 4 ]
  [ "$(sent_header X-Tags)" = "x,testhost" ]
  [[ $(cat "$(sent body)") == *"\$ sh -c 'exit 3'"*"終了コード: 3"* ]]
}

@test "run: -t, -p and -T override the defaults, -T adding to the default tag" {
  use_env_topic
  run pushme run -t 'nightly build' -p low -T ci,deploy -- false </dev/null
  [ "$status" -eq 1 ]
  [ "$(sent_header X-Title)" = "nightly build" ]
  [ "$(sent_header X-Priority)" = 2 ]
  [ "$(sent_header X-Tags)" = "x,ci,deploy,testhost" ]
}

@test "run: a command that does not exist exits 127 and is reported" {
  use_env_topic
  run -127 --separate-stderr pushme run -- no-such-command-for-pushme arg </dev/null
  [[ $stderr == *"no-such-command-for-pushme: コマンドが見つかりません"* ]]
  [ "$(sent_header_text X-Title)" = "no-such-command-for-pushme 失敗 (exit 127)" ]
  run -127 pushme run -- ./no/such/path </dev/null
}

@test "run: pushme's own functions and builtins are not runnable as commands" {
  use_env_topic
  run -127 pushme run -- usage </dev/null
  run -127 pushme run -- exit 0 </dev/null
}

@test "run: a program on PATH runs even when pushme has a function of that name" {
  use_env_topic
  mkdir "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho external usage\n' >"$BATS_TEST_TMPDIR/bin/usage"
  chmod +x "$BATS_TEST_TMPDIR/bin/usage"
  PATH=$BATS_TEST_TMPDIR/bin:$PATH run pushme run -q -- usage </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "external usage" ]
}

@test "run: a command killed by a signal is a failure with 128+N" {
  use_env_topic
  run pushme run -- sh -c 'kill -TERM $$' </dev/null
  [ "$status" -eq 143 ]
  [ "$(sent_header X-Tags)" = "x,testhost" ]
  [[ $(cat "$(sent body)") == *"終了コード: 143（SIGTERM）"* ]]
}

@test "run: Ctrl-C stops the command, sends a failure notification and exits 130" {
  use_env_topic
  local ready=$BATS_TEST_TMPDIR/ready
  # set -m gives pushme its own process group, standing in for the terminal's
  # foreground group that receives Ctrl-C.
  run "$PUSHME_TEST_BASH" -c '
    set -m
    "$0" "$1" run -- sh -c "touch \"$2\"; exec sleep 30" &
    pgid=$!
    i=0
    while [ ! -e "$2" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    kill -INT -- -"$pgid"
    wait "$pgid"
  ' "$PUSHME_TEST_BASH" "$PUSHME_BIN" "$ready" </dev/null
  [ "$status" -eq 130 ]
  [ "$(curl_calls)" -eq 1 ]
  [ "$(sent_header_text X-Title)" = "sh 失敗 (exit 130)" ]
  [[ $(cat "$(sent body)") == *"130（SIGINT）"* ]]
}

@test "run: the command's exit code survives a failed notification" {
  use_env_topic
  FAKE_CURL_STATUS=500 run --separate-stderr pushme run -- sh -c 'exit 5' </dev/null
  [ "$status" -eq 5 ]
  [[ $stderr == *"HTTP 500"* ]]
}

@test "run: without a topic the command still runs and keeps its exit code" {
  run --separate-stderr pushme run -- sh -c 'echo ran; exit 4' </dev/null
  [ "$status" -eq 4 ]
  [ "$output" = "ran" ]
  [[ $stderr == *"PUSHME_NTFY_TOPIC"* ]]
  [ "$(curl_calls)" -eq 0 ]
  [[ $(cat "$ERROR_LOG") == *"PUSHME_NTFY_TOPIC"* ]]
}

@test "run: --on-fail-only skips the notification on success only" {
  use_env_topic
  run pushme run --on-fail-only -- true </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 0 ]
  run pushme run --on-fail-only -- false </dev/null
  [ "$status" -eq 1 ]
  [ "$(curl_calls)" -eq 1 ]
}

@test "run: durations are written as 1h2m3s, 2m3s or 3s" {
  run "$PUSHME_TEST_BASH" -c 'source "$1"; for s in 0 3 59 60 123 3600 3723; do format_duration "$s"; printf "%s " "$REPLY"; done' sh "$PUSHME_BIN"
  [ "$output" = "0s 3s 59s 1m0s 2m3s 1h0m0s 1h2m3s " ]
}

@test "run: the elapsed time is measured" {
  use_env_topic
  run pushme run -- sleep 1 </dev/null
  [ "$status" -eq 0 ]
  [[ $(cat "$(sent body)") =~ 所要時間:\ [12]s ]]
}

# --- output ----------------------------------------------------------------------

@test "run: the command's stdout and stderr go to the caller unchanged" {
  use_env_topic
  run --separate-stderr pushme run -q -- sh -c 'echo out; echo err >&2' </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "out" ]
  [ "$stderr" = "err" ]
}

@test "run: the command gets the caller's LC_ALL, not pushme's own" {
  use_env_topic
  run env -u LC_ALL "$PUSHME_TEST_BASH" "$PUSHME_BIN" run -- sh -c 'echo "LC_ALL=${LC_ALL-unset}"' </dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"LC_ALL=unset"* ]]
  LC_ALL=en_US.UTF-8 run pushme run -- sh -c 'echo "LC_ALL=${LC_ALL-unset}"' </dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"LC_ALL=en_US.UTF-8"* ]]
}

@test "run: stdin is passed to the command" {
  use_env_topic
  run pushme run -q -- cat <<<"piped input"
  [ "$output" = "piped input" ]
}

@test "run: pushme's own report goes to stderr, not to the command's stdout" {
  use_env_topic
  run --separate-stderr pushme run -- true </dev/null
  [ -z "$output" ]
  [ "$stderr" = "pushme: 通知を送りました" ]
}

@test "run: --tail adds the last N lines, stderr included, and removes its temp file" {
  use_env_topic
  export TMPDIR=$BATS_TEST_TMPDIR/tmp
  mkdir "$TMPDIR"
  run pushme run -q --tail 2 -- sh -c 'echo line1; echo line2; echo line3; echo line4 >&2' </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'line1\nline2\nline3\nline4')" ]
  local body
  body=$(cat "$(sent body)")
  [[ $body == *"--- 出力の末尾 2 行 ---"$'\n'"line3"$'\n'"line4" ]]
  [[ $body != *line2* ]]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "run: long --tail output keeps its end within 4,000 bytes" {
  use_env_topic
  run pushme run -q --tail 1000 -- sh -c 'i=0; while [ $i -lt 500 ]; do echo "line $i of a long and noisy build log"; i=$((i + 1)); done; echo LAST' </dev/null
  [ "$status" -eq 0 ]
  [ "$(byte_length "$(sent body)")" -le 4000 ]
  [[ $(cat "$(sent body)") == *"…"*"LAST" ]]
}

@test "run: --dry-run runs the command but sends nothing" {
  use_env_topic
  run pushme run --dry-run -- sh -c 'exit 2' </dev/null
  [ "$status" -eq 2 ]
  [ "$(curl_calls)" -eq 0 ]
  [[ $output == *"X-Title: sh 失敗 (exit 2)"* ]]
}

# --- usage errors ------------------------------------------------------------------

@test "run: a missing -- or command is a usage error and nothing runs" {
  use_env_topic
  local marker=$BATS_TEST_TMPDIR/ran
  run -2 pushme run touch "$marker" </dev/null
  run -2 pushme run -- </dev/null
  run -2 pushme run </dev/null
  run -2 pushme run -p 9 -- touch "$marker" </dev/null
  run -2 pushme run --tail 0 -- touch "$marker" </dev/null
  run -2 pushme run --tail x -- touch "$marker" </dev/null
  run -2 pushme run --bogus -- touch "$marker" </dev/null
  [ ! -e "$marker" ]
  [ "$(curl_calls)" -eq 0 ]
}
