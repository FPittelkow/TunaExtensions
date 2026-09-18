#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -lt 5 || -z "$1" ]]; then
  echo "Usage: $0 TUNA_ROOT INSTALL_DIR DERIVED_DATA CONFIGURATION TARGET [TARGET ...]" >&2
  exit 64
fi
TUNA_ROOT="$1"
INSTALL_DIR="$2"
DERIVED_DATA="$3"
CONFIGURATION="$4"
shift 4
TARGETS=("$@")

case "$CONFIGURATION" in
  Debug|Release) ;;
  *) echo "Configuration must be Debug or Release: $CONFIGURATION" >&2; exit 64 ;;
esac

# Resolve the complete selection before preparing TunaKit. Besides failing cheaply, this gives all
# downstream builds the canonical scheme spelling from the single authoritative resolver.
declare -a resolved_targets=()
for target in "${TARGETS[@]}"; do
  IFS=$'\t' read -r _ resolved_target < <("$ROOT/scripts/resolve-extension-scheme.sh" "$target")
  resolved_targets+=("$resolved_target")
done

package="$("$ROOT/scripts/prepare-local-tunakit-package.sh" "$TUNA_ROOT")"
for target in "${resolved_targets[@]}"; do
  TUNA_LOCAL_TUNAKIT_PACKAGE="$package" \
    "$ROOT/scripts/install-local-extension-product.sh" \
      "$target" "$INSTALL_DIR" "$DERIVED_DATA" "$CONFIGURATION"
done
