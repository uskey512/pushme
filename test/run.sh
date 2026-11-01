#!/usr/bin/env bash
# Runs each .bats file in its own bats process, JOBS of them at a time (by
# default one per CPU), and prints every file's output in one piece once all
# are done, so a parallel run reads like a serial one. Arguments narrow the
# run to the given files.

set -u

cd "$(dirname "$0")" || exit 1
jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
out=$(mktemp -d "${TMPDIR:-/tmp}/pushme-tests.XXXXXX") || exit 1
trap 'rm -rf "$out"' EXIT

files=()
if [ $# -gt 0 ]; then
  for file in "$@"; do files+=("${file#test/}"); done
else
  # Largest first, so the longest files do not start last.
  while IFS= read -r file; do files+=("$file"); done < <(ls -S -- *.bats)
fi

# shellcheck disable=SC2016 # expanded by the inner sh
printf '%s\n' "${files[@]}" | xargs -P "$jobs" -I{} sh -c '
  bats "$1" >"$2/$1.out" 2>&1
  echo $? >"$2/$1.status"
' sh {} "$out"

failed=()
for file in $(printf '%s\n' "${files[@]}" | sort); do
  printf '=== %s\n' "$file"
  cat "$out/$file.out" 2>/dev/null
  if [ "$(cat "$out/$file.status" 2>/dev/null)" != 0 ]; then failed+=("$file"); fi
done

passed=$(cat "$out"/*.out 2>/dev/null | grep -c '^ok ')
not_ok=$(cat "$out"/*.out 2>/dev/null | grep -c '^not ok ')
printf '\n%d 件成功、%d 件失敗（%d ファイル、並列 %d）\n' "$passed" "$not_ok" "${#files[@]}" "$jobs"
if [ ${#failed[@]} -gt 0 ]; then
  printf '失敗したファイル: %s\n' "${failed[*]}"
  exit 1
fi
