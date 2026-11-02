#!/usr/bin/env bats

load helpers/common.sh

topic_in_config() {
  sed -n 's/^PUSHME_NTFY_TOPIC=//p' "$CONFIG_FILE"
}

@test "init: an empty first line generates a new 64-character topic" {
  run pushme init <<<""
  [ "$status" -eq 0 ]
  local topic
  topic=$(topic_in_config)
  [[ $topic =~ ^[A-Za-z0-9]{64}$ ]]
  [ "$(printf '%s\n' "$output" | grep -c -F "$topic")" -eq 1 ]
  [[ $output == *"パスワード管理ツール"* ]]
  [[ $output == *"ntfy アプリ"* ]]
}

@test "init: the config directory is 0700 and the file 0600, whatever the umask" {
  run "$PUSHME_TEST_BASH" -c 'umask 000; exec "$0" "$1" init' "$PUSHME_TEST_BASH" "$PUSHME_BIN" </dev/null
  [ "$status" -eq 0 ]
  [ "$(file_mode "$CONFIG_FILE")" = 600 ]
  [ "$(file_mode "$(dirname "$CONFIG_FILE")")" = 700 ]
}

@test "init: generated topics differ between runs" {
  run pushme init </dev/null
  local first
  first=$(topic_in_config)
  run pushme init --force </dev/null
  [ "$status" -eq 0 ]
  [ "$(topic_in_config)" != "$first" ]
}

@test "init: an existing topic is taken from the first line of stdin and not shown" {
  run pushme init < <(printf '%s\nsecond-line\n' "$TEST_TOPIC")
  [ "$status" -eq 0 ]
  [ "$(topic_in_config)" = "$TEST_TOPIC" ]
  refute_secret "$output"
  run ! grep -q second-line "$CONFIG_FILE"
  [ "$(file_mode "$CONFIG_FILE")" = 600 ]
}

@test "init: surrounding whitespace and CR are stripped from a pasted topic" {
  run pushme init < <(printf '  %s \r\n' "$TEST_TOPIC")
  [ "$status" -eq 0 ]
  [ "$(topic_in_config)" = "$TEST_TOPIC" ]
}

@test "init: a pasted topic without a trailing newline is accepted" {
  run pushme init < <(printf '%s' "$TEST_TOPIC")
  [ "$status" -eq 0 ]
  [ "$(topic_in_config)" = "$TEST_TOPIC" ]
}

@test "init: a malformed topic is rejected without writing or echoing it" {
  run -2 pushme init <<<"not valid/secretpart"
  [ ! -e "$CONFIG_FILE" ]
  [[ $output != *secretpart* ]]
}

@test "init: an existing config is left alone unless --force is given" {
  write_config "PUSHME_NTFY_TOPIC=keep-me"
  run pushme init <<<"$TEST_TOPIC"
  [ "$status" -eq 0 ]
  [ "$(topic_in_config)" = "keep-me" ]
  [[ $output == *"既にあります"* ]]
  run pushme init --force <<<"$TEST_TOPIC"
  [ "$status" -eq 0 ]
  [ "$(topic_in_config)" = "$TEST_TOPIC" ]
  [ "$(file_mode "$CONFIG_FILE")" = 600 ]
}

@test "init: the topic cannot be passed as an argument" {
  run -2 pushme init "$TEST_TOPIC" </dev/null
  [ ! -e "$CONFIG_FILE" ]
}

@test "init: without a terminal no test notification is sent" {
  run pushme init <<<"$TEST_TOPIC"
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 0 ]
}

@test "init: the written config is read back by send" {
  run pushme init <<<"$TEST_TOPIC"
  PUSHME_HOSTNAME=testhost run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.sh/$TEST_TOPIC" ]
}
