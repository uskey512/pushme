#!/usr/bin/env bats

load helpers/common.sh

# --- body ----------------------------------------------------------------------

@test "send: joins arguments with spaces and posts to the topic URL" {
  use_env_topic
  run pushme hello  world </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "pushme: 送信しました" ]
  [ "$(curl_calls)" -eq 1 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.sh/$TEST_TOPIC" ]
  [ "$(cat "$(sent body)")" = "hello world" ]
}

@test "send: the explicit send subcommand behaves the same" {
  use_env_topic
  run pushme send -t T hello </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = "hello" ]
}

@test "send: reads the body from stdin when there are no arguments" {
  use_env_topic
  run pushme -t T <<<"from stdin"
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = "from stdin" ]
}

@test "send: a lone - reads the body from stdin" {
  use_env_topic
  run pushme -t T - <<<"dash body"
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = "dash body" ]
}

@test "send: arguments win over piped stdin" {
  use_env_topic
  run pushme from args <<<"ignored"
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = "from args" ]
}

@test "send: -- ends option parsing so a message may start with a dash" {
  use_env_topic
  run pushme -- -5 degrees </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = "-5 degrees" ]
}

@test "send: an empty or blank body is a usage error and nothing is sent" {
  use_env_topic
  run -2 pushme </dev/null
  [[ $output == *"本文が空です"* ]]
  run -2 pushme <<<"   "
  run -2 pushme ""
  [ "$(curl_calls)" -eq 0 ]
}

@test "send: quotes, backslashes, tabs, newlines and a leading @ reach curl unchanged" {
  use_env_topic
  printf '@/etc/passwd "q" back\\slash\ttab\nline2 $(touch x) end\\' >"$BATS_TEST_TMPDIR/in"
  run pushme - <"$BATS_TEST_TMPDIR/in"
  [ "$status" -eq 0 ]
  cmp "$BATS_TEST_TMPDIR/in" "$(sent body)"
}

# --- truncation ---------------------------------------------------------------

@test "send: a body of exactly 4,000 bytes is sent unchanged" {
  use_env_topic
  repeat a 4000 >"$BATS_TEST_TMPDIR/in"
  run pushme - <"$BATS_TEST_TMPDIR/in"
  [ "$status" -eq 0 ]
  cmp "$BATS_TEST_TMPDIR/in" "$(sent body)"
}

@test "send: an ASCII body over 4,000 bytes is cut to 4,000 bytes ending in …" {
  use_env_topic
  repeat a 4001 >"$BATS_TEST_TMPDIR/in"
  { repeat a 3997 && printf '…'; } >"$BATS_TEST_TMPDIR/expected"
  run pushme - <"$BATS_TEST_TMPDIR/in"
  [ "$status" -eq 0 ]
  cmp "$BATS_TEST_TMPDIR/expected" "$(sent body)"
  [ "$(byte_length "$(sent body)")" -eq 4000 ]
}

@test "send: truncation does not split a 3-byte character" {
  use_env_topic
  repeat あ 1400 >"$BATS_TEST_TMPDIR/in"
  { repeat あ 1332 && printf '…'; } >"$BATS_TEST_TMPDIR/expected"
  run pushme - <"$BATS_TEST_TMPDIR/in"
  [ "$status" -eq 0 ]
  cmp "$BATS_TEST_TMPDIR/expected" "$(sent body)"
}

@test "send: truncation does not split a 4-byte emoji" {
  use_env_topic
  { printf ab && repeat 😀 1000; } >"$BATS_TEST_TMPDIR/in"
  { printf ab && repeat 😀 998 && printf '…'; } >"$BATS_TEST_TMPDIR/expected"
  run pushme - <"$BATS_TEST_TMPDIR/in"
  [ "$status" -eq 0 ]
  cmp "$BATS_TEST_TMPDIR/expected" "$(sent body)"
  [ "$(byte_length "$(sent body)")" -le 4000 ]
}

# --- priority -----------------------------------------------------------------

@test "send: priority numbers and names are normalized to 1-5" {
  use_env_topic
  local pair
  for pair in 1:1 min:1 2:2 low:2 3:3 default:3 4:4 high:4 HIGH:4 5:5 urgent:5 max:5; do
    run pushme -p "${pair%%:*}" hi </dev/null
    [ "$status" -eq 0 ]
    [ "$(sent_header X-Priority)" = "${pair#*:}" ]
  done
  run pushme --priority=urgent hi </dev/null
  [ "$(sent_header X-Priority)" = 5 ]
}

@test "send: no priority option sends no priority header" {
  use_env_topic
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  run ! sent_header X-Priority
}

@test "send: an invalid priority is a usage error and nothing is sent" {
  use_env_topic
  local value
  for value in 0 6 9 urgentt foo ''; do
    run -2 pushme -p "$value" hi </dev/null
    [[ $output == *"優先度"* ]]
  done
  [ "$(curl_calls)" -eq 0 ]
}

# --- tags and host --------------------------------------------------------------

@test "send: tags are trimmed and the host name tag is appended last" {
  use_env_topic
  run pushme -T ' a, b ,,c ' hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header X-Tags)" = "a,b,c,testhost" ]
}

@test "send: -T may be repeated" {
  use_env_topic
  run pushme -T a --tags b,c --tags=d hi </dev/null
  [ "$(sent_header X-Tags)" = "a,b,c,d,testhost" ]
}

@test "send: --no-host leaves the host name out" {
  use_env_topic
  run pushme --no-host -T a,b hi </dev/null
  [ "$(sent_header X-Tags)" = "a,b" ]
  run pushme --no-host hi </dev/null
  run ! sent_header X-Tags
}

@test "send: the host name tag defaults to hostname -s" {
  use_env_topic
  unset PUSHME_HOSTNAME
  local expected
  expected=$(hostname -s 2>/dev/null || uname -n)
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header X-Tags)" = "${expected%%.*}" ]
}

# --- headers --------------------------------------------------------------------

@test "send: a Japanese title is sent as an RFC 2047 encoded-word" {
  use_env_topic
  run pushme -t 'ビルド完了 🎉' hi </dev/null
  [ "$status" -eq 0 ]
  local value encoded
  value=$(sent_header X-Title)
  [[ $value == '=?UTF-8?B?'*'?=' ]]
  encoded=${value#=?UTF-8?B?}
  encoded=${encoded%?=}
  [ "$(printf '%s' "$encoded" | base64 --decode)" = 'ビルド完了 🎉' ]
}

@test "send: an ASCII title is sent as is" {
  use_env_topic
  run pushme -t 'Build done' hi </dev/null
  [ "$(sent_header X-Title)" = "Build done" ]
}

@test "send: emoji and Japanese tags are encoded together with the host tag" {
  use_env_topic
  run pushme -T '🔥,タグ' hi </dev/null
  [ "$status" -eq 0 ]
  local value encoded
  value=$(sent_header X-Tags)
  encoded=${value#=?UTF-8?B?}
  encoded=${encoded%?=}
  [ "$(printf '%s' "$encoded" | base64 --decode)" = '🔥,タグ,testhost' ]
}

@test "send: a title containing =? or a newline is encoded, so it cannot add headers" {
  use_env_topic
  run pushme -t 'a =?b?= c' hi </dev/null
  [[ $(sent_header X-Title) == '=?UTF-8?B?'* ]]
  run pushme -t $'line1\nX-Evil: 1' hi </dev/null
  [ "$status" -eq 0 ]
  [[ $(sent_header X-Title) == '=?UTF-8?B?'* ]]
  run ! sent_header X-Evil
}

@test "send: --click and --markdown set their headers" {
  use_env_topic
  run pushme -c https://example.com/run/1 --markdown '**done**' </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header X-Click)" = "https://example.com/run/1" ]
  [ "$(sent_header X-Markdown)" = "yes" ]
}

@test "send: a token adds an Authorization header; without one there is none" {
  use_env_topic
  run pushme hi </dev/null
  run ! sent_header Authorization
  export PUSHME_NTFY_TOKEN=$TEST_TOKEN
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header Authorization)" = "Bearer $TEST_TOKEN" ]
}

@test "send: curl gets the timeouts and the topic and token stay out of its arguments" {
  use_env_topic
  export PUSHME_NTFY_TOKEN=$TEST_TOKEN PUSHME_TIMEOUT=4
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  local args
  args=$(tr '\n' ' ' <"$(sent args)")
  [[ $args == *"--fail "* ]]
  [[ $args == *"--connect-timeout 3 "* ]]
  [[ $args == *"--max-time 4 "* ]]
  refute_secret "$args"
}

@test "send: an invalid PUSHME_TIMEOUT is a usage error" {
  use_env_topic
  PUSHME_TIMEOUT=abc run -2 pushme hi </dev/null
  PUSHME_TIMEOUT=0 run -2 pushme hi </dev/null
  [ "$(curl_calls)" -eq 0 ]
}

# --- configuration errors -------------------------------------------------------

@test "send: a missing topic is a usage error that points to init" {
  run -2 --separate-stderr pushme hi </dev/null
  [[ $stderr == *"PUSHME_NTFY_TOPIC"*"pushme init"* ]]
  [ "$(curl_calls)" -eq 0 ]
}

@test "send: a malformed topic is rejected without echoing it" {
  local topic
  for topic in 'has space-secretpart' 'slash/secretpart' "$(repeat a 65)"; do
    PUSHME_NTFY_TOPIC=$topic run -2 --separate-stderr pushme hi </dev/null
    [[ $stderr == *"形式が不正"* ]]
    [[ $stderr != *secretpart* ]]
    [[ $stderr != *aaaaaaaaaaaaaaaa* ]]
  done
  [ "$(curl_calls)" -eq 0 ]
}

@test "send: a 64-character topic is accepted" {
  PUSHME_NTFY_TOPIC=$(repeat a 64) run pushme hi </dev/null
  [ "$status" -eq 0 ]
}

@test "send: a non-http URL and a token with spaces are usage errors" {
  use_env_topic
  PUSHME_NTFY_URL=ftp://ntfy.sh run -2 pushme hi </dev/null
  PUSHME_NTFY_TOKEN='tk_with space' run -2 --separate-stderr pushme hi </dev/null
  [[ $stderr != *"with space"* ]]
  [ "$(curl_calls)" -eq 0 ]
}

@test "send: an unsupported backend is a usage error" {
  use_env_topic
  PUSHME_BACKEND=carrier_pigeon run -2 --separate-stderr pushme hi </dev/null
  [[ $stderr == *"carrier_pigeon"* ]] || false
}

@test "send: unknown options and options missing a value are usage errors" {
  use_env_topic
  run -2 pushme -x hi </dev/null
  run -2 pushme -t </dev/null
  run -2 pushme -q -p </dev/null
  [ "$(curl_calls)" -eq 0 ]
}

@test "send: options end at the first message word" {
  use_env_topic
  run pushme -q "done" -p 9 </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = "done -p 9" ]
}

# --- output ----------------------------------------------------------------------

@test "send: --quiet prints nothing on success" {
  use_env_topic
  run pushme -q hi </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "send: --dry-run prints the request with the topic and token masked and sends nothing" {
  use_env_topic
  export PUSHME_NTFY_TOKEN=$TEST_TOKEN
  run pushme --dry-run -t 'ビルド' -p high -T a -c https://example.com --markdown hello </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 0 ]
  refute_secret "$output"
  [[ $output == *"POST https://ntfy.sh/pus…(26 chars)"* ]]
  [[ $output == *"Authorization: Bearer tk_t…(32 chars)"* ]]
  [[ $output == *"X-Title: ビルド"* ]]
  [[ $output == *"X-Priority: 4"* ]]
  [[ $output == *"X-Tags: a,testhost"* ]]
  [[ $output == *"X-Click: https://example.com"* ]]
  [[ $output == *"X-Markdown: yes"* ]]
  [[ $output == *"hello"* ]]
}

# --- failures ----------------------------------------------------------------------

@test "send: an HTTP error exits 1 with one line on stderr and a log entry, without the topic" {
  use_env_topic
  export FAKE_CURL_STATUS=500
  run -1 --separate-stderr pushme hi </dev/null
  [ "${#stderr_lines[@]}" -eq 1 ]
  [[ $stderr == "pushme: エラー: 送信に失敗しました: HTTP 500" ]]
  refute_secret "$output" "$stderr"
  [ -f "$ERROR_LOG" ]
  local log
  log=$(cat "$ERROR_LOG")
  [[ $log =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}.*HTTP\ 500 ]]
  refute_secret "$log"
}

@test "send: secrets inside curl's own error message are masked" {
  use_env_topic
  export PUSHME_NTFY_TOKEN=$TEST_TOKEN FAKE_CURL_EXITS=6
  export FAKE_CURL_STDERR="curl: (6) failed for https://ntfy.sh/$TEST_TOPIC with $TEST_TOKEN"
  run -1 --separate-stderr pushme hi </dev/null
  refute_secret "$stderr" "$(cat "$ERROR_LOG")"
  [[ $stderr == *"https://ntfy.sh/pus…(26 chars) with tk_t…(32 chars)"* ]]
}

@test "send: HTTP 429 is not retried" {
  use_env_topic
  export FAKE_CURL_STATUS=429
  run -1 --separate-stderr pushme hi </dev/null
  [ "$(curl_calls)" -eq 1 ]
  [[ $stderr == *"429"* ]]
}

@test "send: a redirect is a failure, not a delivery" {
  use_env_topic
  FAKE_CURL_STATUS=301 run -1 --separate-stderr pushme hi </dev/null
  [[ $stderr == *"HTTP 301"* ]]
  [ "$(curl_calls)" -eq 1 ]
}

@test "send: a refused connection is retried once" {
  use_env_topic
  FAKE_CURL_EXITS="7 0" run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 2 ]
}

@test "send: a connection refused twice fails after two attempts" {
  use_env_topic
  FAKE_CURL_EXITS=7 run -1 --separate-stderr pushme hi </dev/null
  [ "$(curl_calls)" -eq 2 ]
  [[ $stderr == *"curl: (7)"* ]]
}

@test "send: a timeout is not retried" {
  use_env_topic
  FAKE_CURL_EXITS=28 run -1 pushme hi </dev/null
  [ "$(curl_calls)" -eq 1 ]
}

@test "send: a missing curl is a send failure" {
  use_env_topic
  PUSHME_CURL=$BATS_TEST_TMPDIR/no-such-curl run -1 --separate-stderr pushme hi </dev/null
  [[ $stderr == *"curl が見つかりません"* ]]
}

@test "send: the error log is trimmed once it grows past 100 KB" {
  use_env_topic
  mkdir -p "$(dirname "$ERROR_LOG")"
  repeat "$(repeat x 99)
" 1500 >"$ERROR_LOG"
  FAKE_CURL_STATUS=503 run -1 pushme hi </dev/null
  [ "$(byte_length "$ERROR_LOG")" -le 102400 ]
  [[ $(tail -n 1 "$ERROR_LOG") == *"HTTP 503" ]]
  [[ $(head -n 1 "$ERROR_LOG") == "$(repeat x 99)" ]]
}

# --- ntfy limits -------------------------------------------------------------------

@test "send: a title over 1,000 bytes is cut without splitting a character" {
  use_env_topic
  run pushme -t "$(repeat あ 1400)" hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header_text X-Title)" = "$(repeat あ 332)…" ]
  run pushme -t "$(repeat a 1001)" hi </dev/null
  [ "$(sent_header_text X-Title)" = "$(repeat a 997)…" ]
  run pushme -t "$(repeat a 1000)" hi </dev/null
  [ "$(sent_header X-Title)" = "$(repeat a 1000)" ]
}

@test "send: tags over 512 bytes drop the caller's last tags but keep the host tag" {
  use_env_topic
  local tag60 tags='' i
  tag60=$(repeat t 60)
  for i in 1 2 3 4 5 6 7 8 9 10; do tags=$tags,$i$tag60; done
  run --separate-stderr pushme -T "$tags" hi </dev/null
  [ "$status" -eq 0 ]
  # 8 bytes of host tag + 8 tags of 61 bytes = 496; a ninth would make 557.
  [[ $stderr == *"512 バイト"*"末尾の 2 個"* ]]
  [ "$(sent_header X-Tags)" = "1$tag60,2$tag60,3$tag60,4$tag60,5$tag60,6$tag60,7$tag60,8$tag60,testhost" ]
}

@test "send: tags that exactly fit are all kept without a warning" {
  use_env_topic
  run --separate-stderr pushme -T "$(repeat a 252),$(repeat b 252)" hi </dev/null
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(sent_header X-Tags)" = "$(repeat a 252),$(repeat b 252),testhost" ]
}
