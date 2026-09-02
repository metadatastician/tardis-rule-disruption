#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# check-text-format.sh [repo_root] — fail on trailing whitespace or a missing
# final newline in any git-tracked text file. Exit 1 on the first class found.
set -euo pipefail
root="${1:-.}"
cd "$root"
status=0
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  case "$f" in LICENSE|LICENSES/*) continue;; esac   # verbatim upstream licence texts
  if grep -qI . "$f" 2>/dev/null; then :; else continue; fi   # skip binary
  if grep -nE '[[:space:]]+$' "$f" >/dev/null; then
    echo "trailing whitespace: $f" >&2; status=1
  fi
  if [ -s "$f" ] && [ "$(tail -c1 "$f" | od -An -c | tr -d ' ')" != '\n' ]; then
    echo "missing final newline: $f" >&2; status=1
  fi
done < <(git ls-files -z)
[ "$status" -eq 0 ] && echo "PASS: text format clean"
exit "$status"
