#!/usr/bin/env bats

load helpers/common.sh

make_file() {
  printf '%s' "$2" >"$BATS_TEST_TMPDIR/$1"
  printf '%s' "$BATS_TEST_TMPDIR/$1"
}

@test "attach: --attach uploads the file with PUT and moves the text to X-Message" {
  use_env_topic
  local file
  file=$(make_file build.log 'file content')
  run pushme -a "$file" -t Build 'the message' </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent method)")" = PUT ]
  cmp "$file" "$(sent upload)"
  [ "$(sent_header Filename)" = build.log ]
  [ "$(sent_header X-Message)" = "the message" ]
  [ "$(sent_header X-Title)" = Build ]
  [ ! -e "$(sent body)" ]
}

@test "attach: --filename sets the name shown for the file" {
  use_env_topic
  local file
  file=$(make_file build.log x)
  run pushme --attach="$file" --filename 'レポート.txt' hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header_text Filename)" = 'レポート.txt' ]
}

@test "attach: a multi-line Japanese message is RFC 2047 encoded in X-Message" {
  use_env_topic
  local file
  file=$(make_file a.txt x)
  run pushme -a "$file" "$(printf 'ビルド失敗\n詳細は添付')" </dev/null
  [ "$status" -eq 0 ]
  [[ $(sent_header X-Message) == '=?UTF-8?B?'* ]]
  [ "$(sent_header_text X-Message)" = "$(printf 'ビルド失敗\n詳細は添付')" ]
}

@test "attach: the X-Message text is cut to 4,000 bytes" {
  use_env_topic
  local file
  file=$(make_file a.txt x)
  repeat a 5000 >"$BATS_TEST_TMPDIR/in"
  run pushme -a "$file" - <"$BATS_TEST_TMPDIR/in"
  [ "$status" -eq 0 ]
  sent_header_text X-Message >"$BATS_TEST_TMPDIR/message"
  { repeat a 3997 && printf '…'; } >"$BATS_TEST_TMPDIR/expected"
  cmp "$BATS_TEST_TMPDIR/expected" "$BATS_TEST_TMPDIR/message"
}

@test "attach: a file may be sent without a message" {
  use_env_topic
  local file
  file=$(make_file a.txt x)
  run pushme -a "$file" </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent method)")" = PUT ]
  run ! sent_header X-Message
}

@test "attach: a missing, unreadable or non-regular file is a usage error" {
  use_env_topic
  run -2 --separate-stderr pushme -a "$BATS_TEST_TMPDIR/missing" hi </dev/null
  [[ $stderr == *"添付ファイルを読めません"* ]]
  run -2 pushme -a "$BATS_TEST_TMPDIR" hi </dev/null
  if [ "$(id -u)" -ne 0 ]; then
    local file
    file=$(make_file secret.txt x)
    chmod 000 "$file"
    run -2 pushme -a "$file" hi </dev/null
  fi
  [ "$(curl_calls)" -eq 0 ]
}

@test "attach: a file over PUSHME_NTFY_ATTACH_MAX is left out with a warning" {
  use_env_topic
  local file
  file=$(make_file big.bin 12345)
  PUSHME_NTFY_ATTACH_MAX=4 run --separate-stderr pushme -a "$file" 'see attachment' </dev/null
  [ "$status" -eq 0 ]
  [[ $stderr == *"警告"*"big.bin（5 バイト）"*"4 バイト"* ]]
  [ "$(cat "$(sent method)")" = POST ]
  [[ $(cat "$(sent body)") == "see attachment"$'\n\n'*"big.bin（5 バイト）"* ]]
  run ! sent_header Filename
  PUSHME_NTFY_ATTACH_MAX=5 run pushme -a "$file" hi </dev/null
  [ "$(cat "$(sent method)")" = PUT ]
}

@test "attach: the default limit is the ntfy.sh free tier's 2 MiB" {
  use_env_topic
  local file=$BATS_TEST_TMPDIR/two-mib
  dd if=/dev/zero of="$file" bs=1048576 count=2 2>/dev/null
  run pushme -a "$file" hi </dev/null
  [ "$(cat "$(sent method)")" = PUT ]
  printf x >>"$file"
  run pushme -a "$file" hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent method)")" = POST ]
}

@test "attach: --attach-url sends X-Attach with the text as the body" {
  use_env_topic
  run pushme --attach-url https://example.com/report.pdf --filename report.pdf hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent method)")" = POST ]
  [ "$(sent_header X-Attach)" = "https://example.com/report.pdf" ]
  [ "$(sent_header Filename)" = report.pdf ]
  [ "$(cat "$(sent body)")" = hi ]
}

@test "attach: --attach with --attach-url, or --filename alone, is a usage error" {
  use_env_topic
  local file
  file=$(make_file a.txt x)
  run -2 --separate-stderr pushme -a "$file" --attach-url https://example.com/x hi </dev/null
  [[ $stderr == *"同時に指定できません"* ]]
  run -2 pushme --filename a.txt hi </dev/null
  [ "$(curl_calls)" -eq 0 ]
}

@test "attach: --dry-run shows the upload and sends nothing" {
  use_env_topic
  local file
  file=$(make_file a.txt 'abc')
  run pushme --dry-run -a "$file" hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 0 ]
  [[ $output == *"PUT https://ntfy.sh/pus…(26 chars)"* ]]
  [[ $output == *"Filename: a.txt"* ]]
  [[ $output == *"X-Message: hi"* ]]
  [[ $output == *"添付ファイル: $file（3 バイト）"* ]]
}

@test "attach: run can attach a file the command wrote" {
  use_env_topic
  local file=$BATS_TEST_TMPDIR/out.log
  run pushme run -a "$file" -- sh -c "echo result >'$file'" </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent method)")" = PUT ]
  [ "$(cat "$(sent upload)")" = result ]
  [[ $(sent_header_text X-Message) == *"終了コード: 0"* ]]
}

@test "attach: run still notifies without the file when it is missing" {
  use_env_topic
  run --separate-stderr pushme run -a "$BATS_TEST_TMPDIR/never-written" -- sh -c 'exit 6' </dev/null
  [ "$status" -eq 6 ]
  [[ $stderr == *"添付せずに送ります"* ]]
  [ "$(cat "$(sent method)")" = POST ]
  run ! sent_header Filename
}
