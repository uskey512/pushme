#!/usr/bin/env bats

load helpers/common.sh

PO_TOKEN=atesttokentesttokentesttokenab
PO_USER=usertestusertestusertestuserab

use_pushover() {
  export PUSHME_BACKEND=pushover PUSHME_PUSHOVER_TOKEN=$PO_TOKEN PUSHME_PUSHOVER_USER=$PO_USER
  export PUSHME_HOSTNAME=testhost
}

form() {
  cat "$(sent "form-$1")"
}

refute_keys() {
  local text
  for text in "$@"; do
    case $text in
      *"$PO_TOKEN"* | *"$PO_USER"*)
        echo "key leaked: $text" >&2
        return 1
        ;;
    esac
  done
}

# --- sending -------------------------------------------------------------------------

@test "pushover: posts the form fields to messages.json" {
  use_pushover
  run pushme -t Build -c https://example.com/run/1 hello </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://api.pushover.net/1/messages.json" ]
  [ "$(cat "$(sent method)")" = POST ]
  [ "$(form token)" = "$PO_TOKEN" ]
  [ "$(form user)" = "$PO_USER" ]
  [ "$(form message)" = hello ]
  [ "$(form title)" = "Build @testhost" ]
  [ "$(form url)" = https://example.com/run/1 ]
  [ ! -e "$(sent form-priority)" ]
  [ ! -e "$(sent form-device)" ]
}

@test "pushover: the keys stay out of curl's arguments and pushme's output" {
  use_pushover
  run pushme hello </dev/null
  [ "$status" -eq 0 ]
  refute_keys "$output" "$(cat "$(sent args)")"
}

@test "pushover: priorities map to -2, -1, 0, 1 and never to emergency" {
  use_pushover
  local pair
  for pair in 1:-2 min:-2 2:-1 low:-1 3:0 default:0 4:1 high:1 5:1 urgent:1; do
    run pushme -p "${pair%%:*}" hi </dev/null
    [ "$status" -eq 0 ]
    [ "$(form priority)" = "${pair#*:}" ]
  done
}

@test "pushover: emoji tags lead the title and the host closes it; other tags are dropped" {
  use_pushover
  run pushme -t Build -T white_check_mark,ci,rocket hi </dev/null
  [ "$(form title)" = "✅🚀 Build @testhost" ]
  run pushme -t Build -T x,warning --no-host hi </dev/null
  [ "$(form title)" = "❌⚠️ Build" ]
  run pushme -T question hi </dev/null
  [ "$(form title)" = "❓ @testhost" ]
  run pushme -t Build -T ci,deploy hi </dev/null
  [ "$(form title)" = "Build @testhost" ]
}

@test "pushover: a long title is cut to 250 bytes, keeping the host" {
  use_pushover
  run pushme -t "$(repeat あ 300)" hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(form title)" = "$(repeat あ 78)… @testhost" ]
  [ "$(byte_length "$(sent form-title)")" -le 250 ]
}

@test "pushover: a long message is cut to 1,024 bytes" {
  use_pushover
  repeat a 2000 >"$BATS_TEST_TMPDIR/in"
  run pushme - <"$BATS_TEST_TMPDIR/in"
  [ "$status" -eq 0 ]
  [ "$(form message)" = "$(repeat a 1021)…" ]
  [ "$(byte_length "$(sent form-message)")" -eq 1024 ]
}

@test "pushover: --attach-url goes at the end of the message, never cut off" {
  use_pushover
  repeat a 2000 >"$BATS_TEST_TMPDIR/in"
  run pushme --attach-url https://example.com/report.pdf - <"$BATS_TEST_TMPDIR/in"
  [ "$status" -eq 0 ]
  [[ $(form message) == *$'…\n\nhttps://example.com/report.pdf' ]] || false
  [ "$(byte_length "$(sent form-message)")" -le 1024 ]
}

@test "pushover: --markdown is ignored without a warning" {
  use_pushover
  run --separate-stderr pushme --markdown '**hi**' </dev/null
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(form message)" = '**hi**' ]
}

@test "pushover: PUSHME_PUSHOVER_DEVICE targets a device" {
  use_pushover
  export PUSHME_PUSHOVER_DEVICE=phone,tablet
  run pushme hi </dev/null
  [ "$(form device)" = phone,tablet ]
}

@test "pushover: the keys can come from the config file" {
  write_config "PUSHME_BACKEND=pushover" "PUSHME_PUSHOVER_TOKEN=$PO_TOKEN" "PUSHME_PUSHOVER_USER=$PO_USER"
  run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(form user)" = "$PO_USER" ]
}

# --- attachments ---------------------------------------------------------------------

@test "pushover: --attach sends the file as the multipart attachment" {
  use_pushover
  mkdir "$BATS_TEST_TMPDIR/a dir"
  printf 'PNGDATA' >"$BATS_TEST_TMPDIR/a dir/shot.png"
  run pushme -a "$BATS_TEST_TMPDIR/a dir/shot.png" 'see the screenshot' </dev/null
  [ "$status" -eq 0 ]
  [ "$(form attachment)" = PNGDATA ]
  [ "$(cat "$(sent form-attachment.path)")" = "$BATS_TEST_TMPDIR/a dir/shot.png" ]
  [ "$(form message)" = 'see the screenshot' ]
}

@test "pushover: a file without a message uses the file name as the message" {
  use_pushover
  printf 'x' >"$BATS_TEST_TMPDIR/shot.png"
  run pushme -a "$BATS_TEST_TMPDIR/shot.png" </dev/null
  [ "$status" -eq 0 ]
  [ "$(form message)" = shot.png ]
}

@test "pushover: a file over 5 MiB is left out with a warning" {
  use_pushover
  local file=$BATS_TEST_TMPDIR/big.bin
  dd if=/dev/zero of="$file" bs=1048576 count=5 2>/dev/null
  run pushme -a "$file" hi </dev/null
  [ -e "$(sent form-attachment)" ]
  printf x >>"$file"
  run --separate-stderr pushme -a "$file" hi </dev/null
  [ "$status" -eq 0 ]
  [ ! -e "$(sent form-attachment)" ]
  [[ $stderr == *"警告"*"big.bin（5242881 バイト）"* ]] || false
  [[ $(form message) == "hi"$'\n\n'*"5242880 バイト"* ]] || false
}

# --- configuration errors and output ---------------------------------------------------

@test "pushover: missing or malformed keys are usage errors that do not echo the keys" {
  use_pushover
  PUSHME_PUSHOVER_USER='' run -2 --separate-stderr pushme hi </dev/null
  [[ $stderr == *"PUSHME_PUSHOVER_USER"* ]] || false
  PUSHME_PUSHOVER_TOKEN="${PO_TOKEN}!" run -2 --separate-stderr pushme hi </dev/null
  refute_keys "$stderr"
  PUSHME_PUSHOVER_DEVICE='my phone' run -2 pushme hi </dev/null
  [ "$(curl_calls)" -eq 0 ]
}

@test "pushover: --dry-run masks the keys and sends nothing" {
  use_pushover
  run pushme --dry-run -t Build -T white_check_mark -p high hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 0 ]
  refute_keys "$output"
  [[ $output == *"POST https://api.pushover.net/1/messages.json"* ]] || false
  [[ $output == *"token: ate…(30 chars)"* ]] || false
  [[ $output == *"user: use…(30 chars)"* ]] || false
  [[ $output == *"title: ✅ Build @testhost"* ]] || false
  [[ $output == *"priority: 1"* ]] || false
}

@test "pushover: an HTTP 4xx answer quotes Pushover's errors and is not retried" {
  use_pushover
  export FAKE_CURL_STATUS=400
  export FAKE_CURL_BODY="{\"user\":\"invalid\",\"errors\":[\"user identifier is invalid\",\"application token $PO_TOKEN is invalid\"],\"status\":0}"
  run -1 --separate-stderr pushme hi </dev/null
  [ "$(curl_calls)" -eq 1 ]
  [[ $stderr == *"HTTP 400（user identifier is invalid; application token ate…(30 chars) is invalid）"* ]] || false
  refute_keys "$stderr" "$(cat "$ERROR_LOG")"
}

@test "pushover: HTTP 429 names Pushover and is not retried" {
  use_pushover
  FAKE_CURL_STATUS=429 run -1 --separate-stderr pushme hi </dev/null
  [ "$(curl_calls)" -eq 1 ]
  [[ $stderr == *"HTTP 429（pushover のレート制限"* ]] || false
}

# --- doctor ------------------------------------------------------------------------------

@test "pushover: doctor validates the keys through users/validate.json without sending" {
  use_pushover
  export PUSHME_PUSHOVER_DEVICE=phone FAKE_CURL_BODY='{"status":1,"group":0,"devices":["phone"]}'
  run pushme doctor </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
  [ "$(cat "$(sent url)")" = "https://api.pushover.net/1/users/validate.json" ]
  [ "$(form token)" = "$PO_TOKEN" ]
  [ "$(form device)" = phone ]
  [ ! -e "$(sent form-message)" ]
  refute_keys "$output" "$(cat "$(sent args)")"
  [[ $output == *"[OK] Pushover: キーを確認できました"* ]] || false
}

@test "pushover: doctor reports rejected keys" {
  use_pushover
  export FAKE_CURL_STATUS=400 FAKE_CURL_BODY='{"user":"invalid","errors":["user key is invalid"],"status":0}'
  run -1 pushme doctor </dev/null
  [[ $output == *"[NG] Pushover: キーを確認できません（HTTP 400）: user key is invalid"* ]] || false
}

@test "pushover: doctor reports missing keys without calling the API" {
  export PUSHME_BACKEND=pushover
  run -1 pushme doctor </dev/null
  [[ $output == *"[NG] Pushover: PUSHME_PUSHOVER_TOKEN が未設定です"* ]] || false
  [[ $output == *"[NG] Pushover: PUSHME_PUSHOVER_USER が未設定です"* ]] || false
  [ "$(curl_calls)" -eq 0 ]
}
