#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Team ID}"
BUNDLE_ID="${BUNDLE_ID:-org.jiujinglab.ios}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
xcodebuild -project JiuJing.xcodeproj -scheme JiuJing -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/JiuJing.xcarchive \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" -allowProvisioningUpdates archive
