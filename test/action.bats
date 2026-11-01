#!/usr/bin/env bats
# Runs action/run.sh with the environment the step in action.yml gives it.

load helpers/common.sh

RUN_URL=https://github.com/owner/repo/actions/runs/42

setup_action() {
  export INPUT_MESSAGE=hello INPUT_TOPIC=$TEST_TOPIC INPUT_TITLE='' INPUT_PRIORITY=high
  export INPUT_TAGS='' INPUT_CLICK=$RUN_URL INPUT_SERVER=https://ntfy.sh INPUT_TOKEN=''
  export INPUT_MARKDOWN=false INPUT_ATTACH='' INPUT_DRY_RUN=false INPUT_FAIL_ON_ERROR=false
  export PUSHME_HOSTNAME=owner/repo GITHUB_ACTION_PATH=$PUSHME_ROOT
  export GITHUB_OUTPUT=$BATS_TEST_TMPDIR/github-output RUNNER_TEMP=$BATS_TEST_TMPDIR
  : >"$GITHUB_OUTPUT"
}

run_action() {
  run --separate-stderr "$PUSHME_TEST_BASH" "$PUSHME_ROOT/action/run.sh" </dev/null
}

# Value of a step output written in GITHUB_OUTPUT's NAME<<DELIMITER form.
output_value() {
  awk -v name="$1" '
    index($0, name "<<") == 1 { delimiter = substr($0, length(name) + 3); inside = 1; value = ""; n = 0; next }
    inside && $0 == delimiter { inside = 0; print value; next }
    inside { value = (n++ ? value "\n" : "") $0 }
  ' "$GITHUB_OUTPUT"
}

@test "action: sends with the defaults of action.yml" {
  setup_action
  run_action
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.sh/$TEST_TOPIC" ]
  [ "$(cat "$(sent body)")" = hello ]
  [ "$(sent_header X-Priority)" = 4 ]
  [ "$(sent_header X-Tags)" = owner/repo ]
  [ "$(sent_header X-Click)" = "$RUN_URL" ]
  [ "$(output_value status)" = sent ]
}

@test "action: every input reaches pushme" {
  setup_action
  printf 'log' >"$BATS_TEST_TMPDIR/build.log"
  export INPUT_TITLE='ビルド失敗' INPUT_PRIORITY=urgent INPUT_TAGS=x,ci INPUT_MARKDOWN=true
  export INPUT_SERVER=https://ntfy.example.test/ INPUT_TOKEN=$TEST_TOKEN
  export INPUT_ATTACH=$BATS_TEST_TMPDIR/build.log
  run_action
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.example.test/$TEST_TOPIC" ]
  [ "$(cat "$(sent method)")" = PUT ]
  [ "$(sent_header_text X-Title)" = 'ビルド失敗' ]
  [ "$(sent_header X-Priority)" = 5 ]
  [ "$(sent_header X-Tags)" = x,ci,owner/repo ]
  [ "$(sent_header X-Markdown)" = yes ]
  [ "$(sent_header Authorization)" = "Bearer $TEST_TOKEN" ]
  [ "$(sent_header X-Message)" = hello ]
}

@test "action: input values never run as shell code" {
  setup_action
  local marker=$BATS_TEST_TMPDIR/injected
  export INPUT_MESSAGE="\$(touch $marker) \`touch $marker\` \"; touch $marker; \""
  export INPUT_TITLE="\$(touch $marker)" INPUT_TAGS="a\`touch $marker\`"
  run_action
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  [ "$(cat "$(sent body)")" = "$INPUT_MESSAGE" ]
}

@test "action: a message starting with a dash is sent as is" {
  setup_action
  export INPUT_MESSAGE='-p 1 --dry-run'
  run_action
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = '-p 1 --dry-run' ]
}

@test "action: the topic and token are masked and printed nowhere else" {
  setup_action
  export INPUT_TOKEN=$TEST_TOKEN
  run_action
  [ "$status" -eq 0 ]
  [[ $output == *"::add-mask::$TEST_TOPIC"* ]] || false
  [[ $output == *"::add-mask::$TEST_TOKEN"* ]] || false
  refute_secret "$(grep -v '^::add-mask::' <<<"$output")" "$stderr"
}

@test "action: a topic set on the job is used when the input is empty" {
  setup_action
  export INPUT_TOPIC='' PUSHME_NTFY_TOPIC=$TEST_TOPIC
  run_action
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent url)")" = "https://ntfy.sh/$TEST_TOPIC" ]
  [[ $output == *"::add-mask::$TEST_TOPIC"* ]] || false
}

@test "action: dry-run sends nothing and returns the masked request as an output" {
  setup_action
  export INPUT_DRY_RUN=true INPUT_TITLE='セルフテスト' INPUT_TAGS=test
  run_action
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 0 ]
  [ "$(output_value status)" = dry-run ]
  local request
  request=$(output_value dry-run-output)
  refute_secret "$request"
  [[ $request == *"POST https://ntfy.sh/pus…(26 chars)"$'\n'* ]] || false
  [[ $request == *$'\n'"X-Title: セルフテスト"$'\n'* ]] || false
  [[ $request == *$'\n'"X-Tags: test,owner/repo"$'\n'* ]] || false
  [[ $request == *$'\n'"X-Click: $RUN_URL"$'\n'* ]] || false
  [[ $request == *$'\n'hello ]] || false
}

@test "action: a failed notification only warns by default" {
  setup_action
  FAKE_CURL_STATUS=500 run_action
  [ "$status" -eq 0 ]
  [[ $output == *"::warning title=pushme::通知を送れませんでした: 送信に失敗しました: HTTP 500"* ]] || false
  [ "$(output_value status)" = failed ]
}

@test "action: fail-on-error makes a failed notification fail the step" {
  setup_action
  export INPUT_FAIL_ON_ERROR=true
  FAKE_CURL_STATUS=500 run_action
  [ "$status" -eq 1 ]
  [[ $output == *"::error title=pushme::通知を送れませんでした: 送信に失敗しました: HTTP 500"* ]] || false
  [ "$(output_value status)" = failed ]
}

@test "action: invalid inputs are reported through the same warning" {
  setup_action
  export INPUT_PRIORITY=loudest
  run_action
  [ "$status" -eq 0 ]
  [[ $output == *"::warning title=pushme::通知を送れませんでした: 優先度の値が不正です: loudest"* ]] || false
  export INPUT_PRIORITY=high INPUT_MARKDOWN=yes
  run_action
  [ "$status" -eq 0 ]
  [[ $output == *"::warning title=pushme::通知を送れませんでした: markdown は true か false"* ]] || false
  [ "$(curl_calls)" -eq 0 ]
}

@test "action: an invalid fail-on-error is an error" {
  setup_action
  export INPUT_FAIL_ON_ERROR=maybe
  run_action
  [ "$status" -eq 1 ]
  [[ $output == "::error title=pushme::fail-on-error は true か false にしてください" ]] || false
}

@test "action: workflow command data is escaped in annotations" {
  setup_action
  export FAKE_CURL_EXITS=6 FAKE_CURL_STDERR='curl: (6) 100% failed'
  run_action
  [ "$status" -eq 0 ]
  [[ $output == *"::warning title=pushme::通知を送れませんでした: 送信に失敗しました: curl: (6) 100%25 failed"* ]] || false
}

@test "action: works without GITHUB_OUTPUT" {
  setup_action
  unset GITHUB_OUTPUT
  run_action
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
}

@test "action: action.yml passes every input through env and none into run" {
  local input env_name line
  while IFS= read -r input; do
    env_name=INPUT_$(printf '%s' "$input" | tr 'a-z-' 'A-Z_')
    grep -q -x "        $env_name: \${{ inputs.$input }}" "$PUSHME_ROOT/action.yml"
  done < <(awk '/^inputs:/ { inside = 1; next } /^[^ ]/ { inside = 0 } inside && /^  [a-z-]+:$/ { sub(/:$/, ""); sub(/^  /, ""); print }' "$PUSHME_ROOT/action.yml")
  while IFS= read -r line; do
    [[ $line =~ ^\ +INPUT_[A-Z_]+:\ \$\{\{\ inputs\.[a-z-]+\ \}\}$ ]] || false
  done < <(grep -F '${{ inputs.' "$PUSHME_ROOT/action.yml" | grep -v '^    value:')
}
