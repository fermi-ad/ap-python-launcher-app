#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_ROOT/frontend"

export PATH="$REPO_ROOT/frontend/.fvm/flutter_sdk/bin:$PATH"

exec dart run dart_pre_commit
