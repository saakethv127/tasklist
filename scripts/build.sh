#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(pwd)/dist/Tasklist.app"
xcodebuild -quiet -project Tasklist.xcodeproj -scheme Tasklist \
    -configuration Release -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath .build/xcode build
mkdir -p dist
ditto .build/xcode/Build/Products/Release/Tasklist.app "$APP"
printf 'Built %s\n' "$APP"
