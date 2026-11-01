#!/usr/bin/env bats

load helpers/common.sh

# Sends one message at HHMM $2 with PUSHME_DND=$1 and checks whether it went
# out ($3 = sent) or was held back ($3 = held).
check_at() {
  local before
  before=$(curl_calls)
  PUSHME_DND=$1 PUSHME_TEST_NOW=$2 run pushme -q hi </dev/null
  [ "$status" -eq 0 ]
  if [ "$3" = sent ]; then
    [ "$(curl_calls)" -eq $((before + 1)) ] || {
      echo "expected a send at $2 with $1" >&2
      return 1
    }
  else
    [ "$(curl_calls)" -eq "$before" ] || {
      echo "expected no send at $2 with $1" >&2
      return 1
    }
  fi
}

# --- the time ranges --------------------------------------------------------------------

@test "dnd: a range wrapping past midnight includes its start and excludes its end" {
  use_env_topic
  check_at 23:00-07:00 2259 sent
  check_at 23:00-07:00 2300 held
  check_at 23:00-07:00 2330 held
  check_at 23:00-07:00 0000 held
  check_at 23:00-07:00 0659 held
  check_at 23:00-07:00 0700 sent
  check_at 23:00-07:00 1200 sent
}

@test "dnd: a range within the day" {
  use_env_topic
  check_at 12:00-13:00 1159 sent
  check_at 12:00-13:00 1200 held
  check_at 12:00-13:00 1259 held
  check_at 12:00-13:00 1300 sent
}

@test "dnd: several ranges, spaces and single-digit hours" {
  use_env_topic
  check_at '23:00-07:00, 12:00-13:00' 1230 held
  check_at '23:00-07:00, 12:00-13:00' 0130 held
  check_at '23:00-07:00, 12:00-13:00' 0800 sent
  check_at 7:00-9:30 0700 held
  check_at 7:00-9:30 0929 held
  check_at 7:00-9:30 0930 sent
  check_at 22:00-1:00 0059 held
  check_at 22:00-1:00 0100 sent
}

@test "dnd: malformed settings are usage errors" {
  use_env_topic
  local value
  for value in 23:00 25:00-07:00 23:60-07:00 23:0-07:00 '23:00-07:00,' 'abc' 23:00-07:00-08:00 2300-0700; do
    PUSHME_DND=$value run -2 --separate-stderr pushme hi </dev/null
    [[ $stderr == *"PUSHME_DND の形式が不正です"* ]] || false
  done
  PUSHME_DND=23:00-23:00 run -2 --separate-stderr pushme hi </dev/null
  [[ $stderr == *"始まりと終わりが同じです"* ]] || false
  PUSHME_DND=23:00-07:00 PUSHME_DND_MODE=mute run -2 pushme hi </dev/null
  PUSHME_DND=23:00-07:00 PUSHME_DND_TZ='Asia/Tokyo; rm' run -2 pushme hi </dev/null
  [ "$(curl_calls)" -eq 0 ]
}

@test "dnd: the settings can come from the config file" {
  write_config "PUSHME_NTFY_TOPIC=$TEST_TOPIC" "PUSHME_DND=23:00-07:00" "PUSHME_DND_MODE=quiet"
  PUSHME_TEST_NOW=2330 run pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header X-Priority)" = 1 ]
}

# --- skip and quiet -------------------------------------------------------------------------

@test "dnd: skip sends nothing, exits 0 and says why on stderr" {
  use_env_topic
  PUSHME_DND=23:00-07:00 PUSHME_TEST_NOW=2330 run --separate-stderr pushme hi </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = "pushme: おやすみ時間（23:00-07:00）のため送りませんでした" ]
  [ "$(curl_calls)" -eq 0 ]
  PUSHME_DND=23:00-07:00 PUSHME_TEST_NOW=2330 run --separate-stderr pushme -q hi </dev/null
  [ -z "$stderr" ]
}

@test "dnd: quiet sends with priority 1 and keeps tags and body" {
  use_env_topic
  export PUSHME_DND=23:00-07:00 PUSHME_DND_MODE=quiet PUSHME_TEST_NOW=0100
  run pushme -p high -T build hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header X-Priority)" = 1 ]
  [ "$(sent_header X-Tags)" = build,testhost ]
  [ "$(cat "$(sent body)")" = hi ]
}

@test "dnd: priority 5 always goes through" {
  use_env_topic
  export PUSHME_DND=23:00-07:00 PUSHME_TEST_NOW=0100
  run pushme -p urgent hi </dev/null
  [ "$(sent_header X-Priority)" = 5 ]
  PUSHME_DND_MODE=quiet run pushme -p 5 hi </dev/null
  [ "$(sent_header X-Priority)" = 5 ]
}

@test "dnd: --ignore-dnd sends as usual" {
  use_env_topic
  export PUSHME_DND=23:00-07:00 PUSHME_TEST_NOW=0100
  run pushme --ignore-dnd -p high hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(sent_header X-Priority)" = 4 ]
}

@test "dnd: Pushover's quiet priority is -2" {
  export PUSHME_BACKEND=pushover PUSHME_PUSHOVER_TOKEN=atesttokentesttokentesttokenab
  export PUSHME_PUSHOVER_USER=usertestusertestusertestuserab PUSHME_HOSTNAME=testhost
  export PUSHME_DND=23:00-07:00 PUSHME_DND_MODE=quiet PUSHME_TEST_NOW=0100
  run pushme -p high hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent form-priority)")" = -2 ]
}

@test "dnd: PUSHME_DND_TZ decides which clock is read" {
  use_env_topic
  local hour range
  # From an hour before to two hours after the current hour in Tokyo, so the
  # result does not depend on when the test runs. New York, 13 or 14 hours
  # behind, is well outside that range.
  hour=$(TZ=Asia/Tokyo date +%H)
  hour=$((10#$hour))
  range="$(((hour + 23) % 24)):00-$(((hour + 2) % 24)):00"
  PUSHME_DND=$range PUSHME_DND_TZ=Asia/Tokyo run pushme -q hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 0 ]
  PUSHME_DND=$range PUSHME_DND_TZ=America/New_York run pushme -q hi </dev/null
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 1 ]
}

# --- run and hooks ---------------------------------------------------------------------------

@test "dnd: run keeps the command's exit code when nothing is sent" {
  use_env_topic
  export PUSHME_DND=23:00-07:00 PUSHME_TEST_NOW=0100
  run --separate-stderr pushme run -- sh -c 'exit 3' </dev/null
  [ "$status" -eq 3 ]
  [ "$(curl_calls)" -eq 0 ]
  [[ $stderr == *"おやすみ時間（23:00-07:00）のため送りませんでした"* ]] || false
  [[ $stderr != *"通知を送りました"* ]] || false
  PUSHME_DND_MODE=quiet run pushme run -- false </dev/null
  [ "$status" -eq 1 ]
  [ "$(sent_header X-Priority)" = 1 ]
}

@test "dnd: claude-hook holds notifications back but still records the start" {
  use_env_topic
  export PUSHME_DND=23:00-07:00 PUSHME_TEST_NOW=0100
  run --separate-stderr pushme claude-hook <"$FIXTURES/claude/notification-permission.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(curl_calls)" -eq 0 ]
  run --separate-stderr pushme claude-hook <"$FIXTURES/claude/user-prompt-submit.json"
  [ "$status" -eq 0 ]
  [ -f "$XDG_STATE_HOME/pushme/claude/abc12345-6789-4def-8123-456789abcdef" ]
  PUSHME_DND_MODE=quiet run --separate-stderr pushme claude-hook <"$FIXTURES/claude/stop-failure.json"
  [ -z "$output" ]
  [ "$(sent_header X-Priority)" = 1 ]
}

@test "dnd: codex-hook holds notifications back but still records the start" {
  use_env_topic
  export PUSHME_DND=23:00-07:00 PUSHME_TEST_NOW=0100
  run --separate-stderr pushme codex-hook <"$FIXTURES/codex/permission-request.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(curl_calls)" -eq 0 ]
  run --separate-stderr pushme codex-hook <"$FIXTURES/codex/user-prompt-submit.json"
  [ "$status" -eq 0 ]
  [ -f "$XDG_STATE_HOME/pushme/codex/019a1b2c-3d4e-7f80-9a1b-2c3d4e5f6a7b" ]
}

@test "dnd: hooks log malformed settings and still exit 0" {
  use_env_topic
  PUSHME_DND=bedtime run --separate-stderr pushme codex-hook <"$FIXTURES/codex/permission-request.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(curl_calls)" -eq 0 ]
  [[ $(cat "$ERROR_LOG") == *"codex-hook: PUSHME_DND の形式が不正です: bedtime"* ]] || false
}

# --- dry-run and doctor ---------------------------------------------------------------------

@test "dnd: --dry-run tells whether the hours apply and what happens" {
  use_env_topic
  export PUSHME_DND=23:00-07:00
  PUSHME_TEST_NOW=0100 run pushme --dry-run hi </dev/null
  [[ $output == "pushme: dry-run: おやすみ時間（23:00-07:00）のため送りません" ]] || false
  PUSHME_TEST_NOW=0100 PUSHME_DND_MODE=quiet run pushme --dry-run hi </dev/null
  [[ $output == "おやすみ時間（23:00-07:00）: 優先度 1 で送ります"$'\n'* ]] || false
  [[ $output == *$'\n'"X-Priority: 1"$'\n'* ]] || false
  PUSHME_TEST_NOW=0100 run pushme --dry-run -p urgent hi </dev/null
  [[ $output == "おやすみ時間（23:00-07:00）: 優先度 5 のため送ります"$'\n'* ]] || false
  PUSHME_TEST_NOW=0100 run pushme --dry-run --ignore-dnd hi </dev/null
  [[ $output == "おやすみ時間（23:00-07:00）: --ignore-dnd のため送ります"$'\n'* ]] || false
  PUSHME_TEST_NOW=1200 run pushme --dry-run hi </dev/null
  [[ $output == "おやすみ時間: 対象外"$'\n'* ]] || false
  [ "$(curl_calls)" -eq 0 ]
}

@test "dnd: doctor shows the settings and whether they apply now" {
  use_env_topic
  export PUSHME_DND='23:00-07:00,12:00-13:00' PUSHME_DND_MODE=quiet PUSHME_DND_TZ=Asia/Tokyo
  PUSHME_TEST_NOW=1230 run pushme doctor </dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"[OK] おやすみ時間: 23:00-07:00,12:00-13:00（quiet、タイムゾーン Asia/Tokyo）"* ]] || false
  [[ $output == *"[--] 現在はおやすみ時間中です（12:00-13:00）"* ]] || false
  PUSHME_TEST_NOW=0800 run pushme doctor </dev/null
  [[ $output == *"[--] 現在はおやすみ時間の対象外です"* ]] || false
}

@test "dnd: doctor reports malformed settings and an unset DnD" {
  use_env_topic
  run pushme doctor </dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"[--] おやすみ時間: 設定なし"* ]] || false
  PUSHME_DND=23:00 run -1 pushme doctor </dev/null
  [[ $output == *"[NG] PUSHME_DND の形式が不正です: 23:00"* ]] || false
}
