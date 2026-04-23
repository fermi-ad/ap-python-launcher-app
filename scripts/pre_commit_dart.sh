#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="$REPO_ROOT/.fvm/flutter_sdk/bin:$PATH"

cd "$REPO_ROOT/frontend"

exec ../.fvm/flutter_sdk/bin/dart run dart_pre_commit
