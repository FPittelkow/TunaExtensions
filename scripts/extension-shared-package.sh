#!/usr/bin/env bash
set -euo pipefail

# Inspect this project's objects, not workspace references or similarly named files.
plutil -convert json -o - "${1:?Usage: extension-shared-package.sh PROJECT}/project.pbxproj" |
  python3 -c '
import json
import sys

project = json.load(sys.stdin)
if any(
    obj.get("isa") == "XCLocalSwiftPackageReference"
    and obj.get("relativePath") == "../ChromiumExtensionSupport"
    for obj in project.get("objects", {}).values()
):
    print("ChromiumExtensionSupport")
'
