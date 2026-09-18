#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
INSTALL_DIR="${2:-$HOME/Library/Application Support/Tuna/ExtensionsDev}"
DERIVED_DATA="${3:-$ROOT/build/dd-local}"
CONFIGURATION="${4:-Debug}"

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 TARGET [INSTALL_DIR] [DERIVED_DATA] [CONFIGURATION]" >&2
  exit 64
fi

source_path="$(
  "$ROOT/scripts/build-local-extension-product.sh" \
    "$TARGET" \
    "$CONFIGURATION" \
    "platform=macOS,arch=$(uname -m)" \
    "$DERIVED_DATA"
)"
destination="$INSTALL_DIR/$(basename "$source_path")"
"$ROOT/scripts/install-dev-bundle.sh" "$source_path" "$destination"
echo "Installed $TARGET ($CONFIGURATION) against local TunaKit. Restart Tuna to load changed extension code."
