#!/bin/bash
# Fetches the pinned Sparkle framework into Vendor/ and checks its SHA-256 (same value as Sparkle's Package.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.1
SUM=4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a
[ -d Vendor/Sparkle.xcframework ] && exit 0
mkdir -p Vendor && cd Vendor
curl -fsSL -o Sparkle.zip "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip"
echo "$SUM  Sparkle.zip" | shasum -a 256 -c -
unzip -q Sparkle.zip -d tmp && mv tmp/Sparkle.xcframework . && cp tmp/LICENSE Sparkle-LICENSE
rm -rf tmp Sparkle.zip
