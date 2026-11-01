#!/usr/bin/env bats

load helpers/common.sh

@test "cli: on macOS the tests run bin/pushme with bash 3.2" {
  [ "$(uname -s)" = Darwin ] || skip "macOS only"
  run "$PUSHME_TEST_BASH" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"'
  [ "$output" = "3.2" ]
}

@test "cli: help, -h and --help print usage" {
  local arg
  for arg in help -h --help; do
    run pushme "$arg" </dev/null
    [ "$status" -eq 0 ]
    [[ $output == *"使い方:"* ]]
  done
  run pushme send --help </dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"使い方:"* ]]
}

@test "cli: version and --version print the version" {
  local arg
  for arg in version --version; do
    run pushme "$arg" </dev/null
    [ "$status" -eq 0 ]
    [[ $output =~ ^pushme\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
  done
}

@test "cli: a first argument that is not a subcommand is sent as the message" {
  use_env_topic
  run pushme deploy finished </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = "deploy finished" ]
  run pushme -t T init </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$(sent body)")" = "init" ]
  [ ! -e "$CONFIG_FILE" ]
}

@test "cli: unknown arguments to doctor are usage errors" {
  run -2 pushme doctor --bogus </dev/null
}
