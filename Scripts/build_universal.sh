#!/usr/bin/env bash
# Universal (Apple Silicon + Intel) release build of FlowBreak.app.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_app.sh" --universal "$@"
