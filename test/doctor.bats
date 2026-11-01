#!/usr/bin/env bats

load helpers/common.sh

@test "doctor: a healthy setup passes and only GETs /v1/health" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  run pushme doctor </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.sh/v1/health" ]
  [ ! -e "$(sent config)" ]
  [ ! -e "$(sent body)" ]
  refute_secret "$output" "$(cat "$(sent args)")"
  [[ $output == *"[OK] トピック名: 設定済み（26 文字"* ]]
  [[ $output == *"問題は見つかりませんでした"* ]]
}

@test "doctor: the health check follows PUSHME_NTFY_URL" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC" "PUSHME_NTFY_URL=https://ntfy.example.test/"
  run pushme doctor </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.example.test/v1/health" ]
}

@test "doctor: mentions jq as optional for Claude Code hooks" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  run pushme doctor </dev/null
  [[ $output == *"jq: "*"Claude Code の hook を使うなら必要"* ]]
}

@test "doctor: a missing topic is a problem" {
  run -1 pushme doctor </dev/null
  [[ $output == *"[NG] トピック名: 未設定"* ]]
  [[ $output == *"設定ファイル: ありません"* ]]
}

@test "doctor: a malformed topic is a problem and is not shown" {
  write_config "PUSHME_NTFY_TOPIC=bad/secretpart"
  run -1 pushme doctor </dev/null
  [[ $output == *"[NG] トピック名: 形式が不正"* ]]
  [[ $output != *secretpart* ]]
}

@test "doctor: a topic from the environment is enough without a config file" {
  PUSHME_NTFY_TOPIC=$TEST_TOPIC run pushme doctor </dev/null
  [ "$status" -eq 0 ]
}

@test "doctor: an unreachable server is a problem" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  FAKE_CURL_EXITS=7 run -1 pushme doctor </dev/null
  [[ $output == *"[NG] 疎通"* ]]
  [ "$(curl_calls)" -eq 1 ]
}

@test "doctor: an unhealthy answer is a problem" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  FAKE_CURL_BODY='{"healthy":false}' run -1 pushme doctor </dev/null
  [[ $output == *"[NG] 疎通"* ]]
}

@test "doctor: loose permissions are a problem" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  chmod 640 "$CONFIG_FILE"
  run -1 pushme doctor </dev/null
  [[ $output == *"[NG] 設定ファイル $CONFIG_FILE のパーミッションが 640"* ]]
}

@test "doctor: unknown keys and malformed lines are warnings" {
  write_config "$(cat "$FIXTURES/config-unknown-keys")"
  run pushme doctor </dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"[!!] 設定ファイル 2 行目: 未知のキー PUSHME_NTFY_TOPCI"* ]]
  [[ $output == *"[!!] 設定ファイル 3 行目: KEY=VALUE の形式ではない"* ]]
}

@test "doctor: a missing curl is a problem" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  PUSHME_CURL=$BATS_TEST_TMPDIR/no-such-curl run -1 pushme doctor </dev/null
  [[ $output == *"[NG] curl"* ]]
}

@test "doctor: shows the token only as set" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC" "PUSHME_NTFY_TOKEN=$TEST_TOKEN"
  run pushme doctor </dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"アクセストークン: 設定済み（32 文字"* ]]
  refute_secret "$output"
}
