#!/usr/bin/env bash
# ==============================================================================
# Social Account Vault — Build Helper Script
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

cd "${PROJECT_ROOT}" || exit 1

echo "Building Social Account Vault (Swift 6 Complete Concurrency)..."
swift build --configuration debug -Xswiftc -strict-concurrency=complete
echo "Build succeeded."
