#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/tuna-xcodebuild-test.XXXXXX")"
trap '/bin/rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/logs"

cat >"$SANDBOX/bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
printf 'full output marker\n'
printf '/tmp/Example.swift:12:7: error: useful compiler failure\n'
printf 'trailing noise\n'
exit "${FAKE_XCODEBUILD_STATUS:-0}"
EOF
cat >"$SANDBOX/bin/xcsift" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'formatted diagnostics\n'
EOF
chmod +x "$SANDBOX/bin/xcodebuild" "$SANDBOX/bin/xcsift"

PATH="$SANDBOX/bin:/usr/bin:/bin" \
TUNA_XCODEBUILD_LOG_DIR="$SANDBOX/logs" \
  "$ROOT/scripts/run-xcodebuild" --output "$SANDBOX/captured" -- -list \
  >"$SANDBOX/stdout" 2>"$SANDBOX/stderr"
grep -q 'full output marker' "$SANDBOX/captured"
grep -q 'xcodebuild status: SUCCESS' "$SANDBOX/stderr"
[[ "$(find "$SANDBOX/logs" -type f | wc -l | tr -d ' ')" == 1 ]]

set +e
PATH="$SANDBOX/bin:/usr/bin:/bin" \
FAKE_XCODEBUILD_STATUS=65 \
TUNA_XCODEBUILD_LOG_DIR="$SANDBOX/logs" \
  "$ROOT/scripts/run-xcodebuild" build >"$SANDBOX/failure-stdout" 2>"$SANDBOX/failure-stderr"
status=$?
set -e
[[ "$status" -eq 65 ]]
grep -q 'formatted diagnostics' "$SANDBOX/failure-stderr"
grep -q 'First errors:' "$SANDBOX/failure-stderr"
grep -q 'Example.swift:12:7: error: useful compiler failure' "$SANDBOX/failure-stderr"
grep -q 'xcodebuild status: FAILED (exit 65)' "$SANDBOX/failure-stderr"

rm "$SANDBOX/bin/xcsift"
PATH="$SANDBOX/bin:/usr/bin:/bin" \
TUNA_XCODEBUILD_LOG_DIR="$SANDBOX/logs" \
  "$ROOT/scripts/run-xcodebuild" build >"$SANDBOX/plain-stdout" 2>"$SANDBOX/plain-stderr"
grep -q 'xcodebuild status: SUCCESS' "$SANDBOX/plain-stderr"

rg -Uq 'if: always\(\).*\n *uses: actions/upload-artifact@v4.*\n *with:.*\n *name: xcodebuild-.*\n *path: build/xcodebuild' \
  "$ROOT/.github/workflows/ci.yml"

echo "xcodebuild diagnostic wrapper tests passed."
