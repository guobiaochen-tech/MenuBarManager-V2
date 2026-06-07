#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "编译 mbm-scan..."
swiftc \
    -O \
    -sdk $(xcrun --show-sdk-path) \
    -target arm64-apple-macosx14.0 \
    -emit-executable \
    -o .build/mbm-scan \
    Sources/mbm-scan/*.swift \
    -framework Foundation \
    -framework CoreGraphics \
    -framework ApplicationServices \
    -framework AppKit
echo "编译成功: .build/mbm-scan"
echo ""
.build/mbm-scan
