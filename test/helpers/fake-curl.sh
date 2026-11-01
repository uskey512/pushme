#!/usr/bin/env bash
# Stand-in for curl in the tests. Each call N records what it was given:
#   $FAKE_CURL_DIR/N.args     one argument per line
#   $FAKE_CURL_DIR/N.config   raw --config input read from stdin
#   $FAKE_CURL_DIR/N.url      the URL
#   $FAKE_CURL_DIR/N.headers  header values, unescaped, one per line
#   $FAKE_CURL_DIR/N.body     data-raw value, unescaped
#   $FAKE_CURL_DIR/N.upload   copy of the upload-file
#   $FAKE_CURL_DIR/N.method   GET, POST (data-raw, form) or PUT (upload-file)
#   $FAKE_CURL_DIR/N.form-NAME  value of form-string NAME, or a copy of the
#                             file of form NAME=@"path" (path in N.form-NAME.path)
# and $FAKE_CURL_DIR/calls holds the number of calls so far.
#
# Outcome knobs:
#   FAKE_CURL_EXITS   curl exit codes for call 1, 2, ... (the last one repeats); default 0
#   FAKE_CURL_STATUS  HTTP status; with --fail, 400 or above exits 22 like curl
#   FAKE_CURL_BODY    response body printed when --output is not given
#   FAKE_CURL_STDERR  replaces the error message printed on failure

set -u
export LC_ALL=C

dir=${FAKE_CURL_DIR:?FAKE_CURL_DIR must be set}
calls=0
[ -f "$dir/calls" ] && calls=$(cat "$dir/calls")
n=$((calls + 1))
echo "$n" >"$dir/calls"

printf '%s\n' "$@" >"$dir/$n.args"
: >"$dir/$n.headers"

# Decodes a quoted --config value the way curl documents it: \\ \" \n \r \t \v,
# and a backslash before any other character is dropped. Sets REPLY. Fails
# for anything real curl would misread: no quotes, a bare quote inside, or
# a backslash that escapes the closing quote.
unescape() {
  local s=$1 bs=\\ out='' pre c
  case $s in
    \"*\") s=${s:1:${#s}-2} ;;
    *) return 1 ;;
  esac
  while :; do
    case $s in
      *"$bs"*) ;;
      *) break ;;
    esac
    pre=${s%%"$bs"*}
    s=${s#*"$bs"}
    case $pre in
      *\"*) return 1 ;;
    esac
    [ -n "$s" ] || return 1
    c=${s:0:1}
    s=${s:1}
    case $c in
      n) c=$'\n' ;;
      r) c=$'\r' ;;
      t) c=$'\t' ;;
      v) c=$'\v' ;;
    esac
    out=$out$pre$c
  done
  case $s in
    *\"*) return 1 ;;
  esac
  REPLY=$out$s
}

url='' output='' write_out='' config='' fail=0
while [ $# -gt 0 ]; do
  case $1 in
    -f | --fail) fail=1 ;;
    -o | --output) output=$2 && shift ;;
    -w | --write-out) write_out=$2 && shift ;;
    -K | --config) config=$2 && shift ;;
    --connect-timeout | --max-time | -m) shift ;;
    -*) ;;
    *) url=$1 ;;
  esac
  shift
done

method=GET
if [ "$config" = - ]; then
  cat >"$dir/$n.config"
  while IFS= read -r line || [ -n "$line" ]; do
    key=${line%% = *}
    if [ "$key" = "$line" ] || ! unescape "${line#* = }"; then
      echo "fake-curl: curl would misread this config line: $line" >&2
      exit 2
    fi
    case $key in
      url) url=$REPLY ;;
      header) printf '%s\n' "$REPLY" >>"$dir/$n.headers" ;;
      data-raw)
        method=POST
        printf '%s' "$REPLY" >"$dir/$n.body"
        ;;
      upload-file)
        method=PUT
        cp "$REPLY" "$dir/$n.upload" || exit 26
        ;;
      form-string)
        method=POST
        printf '%s' "${REPLY#*=}" >"$dir/$n.form-${REPLY%%=*}"
        ;;
      form)
        method=POST
        name=${REPLY%%=*}
        file=${REPLY#*=@}
        case $file in
          \"*\")
            file=${file:1:${#file}-2}
            file=${file//\\\"/\"}
            file=${file//\\\\/\\}
            ;;
        esac
        printf '%s\n' "$file" >"$dir/$n.form-$name.path"
        cp "$file" "$dir/$n.form-$name" || exit 26
        ;;
    esac
  done <"$dir/$n.config"
fi
printf '%s\n' "$url" >"$dir/$n.url"
echo "$method" >"$dir/$n.method"

# shellcheck disable=SC2086 # split the list into words
set -- ${FAKE_CURL_EXITS:-0}
code=$1
i=1
for c in "$@"; do
  [ "$i" -le "$n" ] && code=$c
  i=$((i + 1))
done

status=${FAKE_CURL_STATUS:-200}
message=''
case $code in
  0)
    if [ "$status" -ge 400 ] && [ "$fail" = 1 ]; then
      code=22
      message="curl: (22) The requested URL returned error: $status"
    fi
    ;;
  7)
    status=000
    message="curl: (7) Failed to connect to fake.invalid port 443 after 0 ms: Couldn't connect to server"
    ;;
  28)
    status=000
    message="curl: (28) Operation timed out after 10000 milliseconds with 0 bytes received"
    ;;
  *)
    status=000
    message="curl: ($code) simulated failure"
    ;;
esac

if [ "$code" -ne 0 ]; then
  printf '%s\n' "${FAKE_CURL_STDERR:-$message}" >&2
elif [ -z "$output" ] || [ "$output" = - ]; then
  healthy='{"healthy":true}'
  printf '%s' "${FAKE_CURL_BODY:-$healthy}"
fi
if [ -n "$write_out" ]; then
  placeholder='%{http_code}'
  write_out=${write_out//"$placeholder"/"$status"}
  printf '%s' "$write_out"
fi
exit "$code"
