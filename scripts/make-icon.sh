#!/bin/bash
# Generates the placeholder app icon in code → Dropshot/Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"

swift scripts/make-icon.swift "$ICONSET"
mkdir -p Dropshot/Resources
iconutil --convert icns --output Dropshot/Resources/AppIcon.icns "$ICONSET"
echo "Wrote Dropshot/Resources/AppIcon.icns"
