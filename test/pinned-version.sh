#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vericto S.A.S.
# SPDX-License-Identifier: Apache-2.0

# Prints "version=X.Y.Z": the CLI version action.yml pins by default.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
v=$(sed -n 's/^ *default: "\([0-9][0-9.]*\)" # pinned-cli-version$/\1/p' "$root/action.yml" | tr -d '\r')
if [ -z "$v" ]; then
  echo "::error::no '# pinned-cli-version' default in action.yml" >&2
  exit 1
fi
echo "version=$v"
