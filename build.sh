#!/bin/sh
set -e
cd "$(dirname "$0")"
LD="-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist"
swiftc -O main.swift -target arm64-apple-macos12 -o airpods-finder-arm64 $LD
swiftc -O main.swift -target x86_64-apple-macos12 -o airpods-finder-x86_64 $LD
lipo -create airpods-finder-arm64 airpods-finder-x86_64 -output airpods-finder
rm airpods-finder-arm64 airpods-finder-x86_64
echo "Built ./airpods-finder"
