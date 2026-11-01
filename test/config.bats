#!/usr/bin/env bats

load helpers/common.sh

@test "config: comments, blank lines, spaces and quotes are handled" {
  write_config "$(cat "$FIXTURES/config-formatted")"
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.example.test/$TEST_TOPIC" ]
  [ "$(sent_header X-Tags)" = "filehost" ]
  [[ $(tr '\n' ' ' <"$(sent args)") == *"--max-time 7 "* ]]
}

@test "config: CRLF line endings are accepted" {
  write_config "$(sed 's/$/\r/' "$FIXTURES/config-formatted")"
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.example.test/$TEST_TOPIC" ]
  [ "$(sent_header X-Tags)" = "filehost" ]
}

@test "config: PUSHME_CONFIG points to another file" {
  export PUSHME_CONFIG=$BATS_TEST_TMPDIR/custom/pushme.conf
  mkdir -m 700 "$BATS_TEST_TMPDIR/custom"
  printf 'PUSHME_NTFY_TOPIC=%s\n' "$TEST_TOPIC" >"$PUSHME_CONFIG"
  chmod 600 "$PUSHME_CONFIG"
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.sh/$TEST_TOPIC" ]
}

@test "config: environment variables override the file" {
  write_config "PUSHME_NTFY_TOPIC=file-topic" "PUSHME_NTFY_URL=https://file.example.test"
  PUSHME_NTFY_TOPIC=$TEST_TOPIC PUSHME_NTFY_URL=https://env.example.test run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://env.example.test/$TEST_TOPIC" ]
}

@test "config: file < environment < command-line option" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC" "PUSHME_HOSTNAME=filehost"
  run pushme hi </dev/null
  [ "$(sent_header X-Tags)" = "filehost" ]
  PUSHME_HOSTNAME=envhost run pushme hi </dev/null
  [ "$(sent_header X-Tags)" = "envhost" ]
  PUSHME_HOSTNAME=envhost run pushme --no-host hi </dev/null
  [ "$status" -eq 0 ]
  run ! sent_header X-Tags
}

@test "config: an empty value counts as unset" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC" "PUSHME_NTFY_URL=" "PUSHME_TIMEOUT=''"
  PUSHME_HOSTNAME=testhost run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.sh/$TEST_TOPIC" ]
  [[ $(tr '\n' ' ' <"$(sent args)") == *"--max-time 10 "* ]]
}

@test "config: the file is never executed" {
  local marker=$BATS_TEST_TMPDIR/executed
  write_config \
    "PUSHME_NTFY_TOPIC=$TEST_TOPIC" \
    "PUSHME_HOSTNAME=\$(touch $marker-1)\`touch $marker-2\`" \
    "touch $marker-3" \
    "PUSHME_UNKNOWN=x; touch $marker-4"
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  local i
  for i in 1 2 3 4; do
    [ ! -e "$marker-$i" ]
  done
  [ "$(sent_header X-Tags)" = "\$(touch $marker-1)\`touch $marker-2\`" ]
}

@test "config: unknown keys and malformed lines are ignored silently by send" {
  write_config "$(cat "$FIXTURES/config-unknown-keys")"
  PUSHME_HOSTNAME=testhost run --separate-stderr pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "config: a group/world readable file warns on stderr but still sends" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  chmod 644 "$CONFIG_FILE"
  PUSHME_HOSTNAME=testhost run --separate-stderr pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
  [[ $stderr == *"警告"*"644"* ]]
}

@test "config: a group/world accessible directory warns on stderr but still sends" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  chmod 755 "$(dirname "$CONFIG_FILE")"
  PUSHME_HOSTNAME=testhost run --separate-stderr pushme hi </dev/null
  [ "$status" -eq 0 ]
  [[ $stderr == *"警告"*"755"* ]]
}

@test "config: 0600 file in a 0700 directory gives no warning" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  PUSHME_HOSTNAME=testhost run --separate-stderr pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "config: an unreadable file is a usage error" {
  [ "$(id -u)" -ne 0 ] || skip "root can read any file"
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC"
  chmod 000 "$CONFIG_FILE"
  run -2 --separate-stderr pushme hi </dev/null
  [[ $stderr == *"設定ファイルを読めません"* ]]
}
