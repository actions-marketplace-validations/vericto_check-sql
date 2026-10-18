#!/usr/bin/env bash
# Usage: verify-checksum.sh FILE CHECKSUM_FILE
#
# Verifies FILE against a cargo-dist `.sha256` file: one line,
# "<64 hex digits> *<file name>" (or "<hex>  <file name>"). Fails when the
# checksum file is malformed, names a different file, or the digest differs.
# Exit 0 on a match, 1 otherwise.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

if [ "$#" -ne 2 ]; then
  echo "usage: $0 FILE CHECKSUM_FILE" >&2
  exit 2
fi
file=$1
sumfile=$2

if [ ! -f "$file" ]; then
  gh_error "checksum: file not found: $file"
  exit 1
fi
if [ ! -s "$sumfile" ]; then
  gh_error "checksum: checksum file missing or empty: $sumfile"
  exit 1
fi

# First non-blank line. cargo-dist writes "<hash> *<name>" plus a blank line.
line=$(grep -m1 -v '^[[:space:]]*$' "$sumfile" | tr -d '\r') || line=
expected=$(printf '%s' "${line%%[[:space:]]*}" | tr 'A-F' 'a-f')
name=${line#"${line%%[[:space:]]*}"}
name=${name#"${name%%[![:space:]]*}"}
name=${name#\*}

if ! matches '^[0-9a-f]{64}$' "$expected"; then
  gh_error "checksum: $sumfile does not hold a SHA-256 digest"
  exit 1
fi
base=$(basename "$file")
if [ -n "$name" ] && [ "$name" != "$base" ]; then
  gh_error "checksum: $sumfile is for '$name', not '$base'"
  exit 1
fi

actual=$(sha256_of "$file")
if [ "$actual" != "$expected" ]; then
  gh_error "checksum mismatch for $base: expected $expected, got $actual. Refusing to install."
  exit 1
fi
echo "SHA-256 OK: $base ($actual)"
