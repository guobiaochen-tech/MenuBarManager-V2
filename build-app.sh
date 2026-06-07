#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="MenuBarManager-V2"
VERSION="2.3"
BUILD_DIR=".build/release"
mkdir -p "$BUILD_DIR"

echo "编译 $APP_NAME..."

swiftc \
    -O \
    -sdk $(xcrun --show-sdk-path) \
    -target arm64-apple-macosx14.0 \
    -emit-executable \
    -o "$BUILD_DIR/$APP_NAME" \
    Sources/mbm-app/*.swift \
    -framework AppKit \
    -framework ScreenCaptureKit \
    -framework ServiceManagement

echo "编译成功"
echo "打包 .app..."

CONTENTS="$APP_NAME.app/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_NAME.app"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# 复制 app 图标
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$RESOURCES/AppIcon.icns"
    echo "已打包 AppIcon.icns"
fi

# 复制菜单栏图标
if [ -f "Resources/statusbar-icon.png" ]; then
    cp Resources/statusbar-icon.png "$RESOURCES/statusbar-icon.png"
    echo "已打包 statusbar-icon.png"
fi

cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.paul.menubar-manager-v2</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSQuitAlwaysKeepsWindows</key>
    <false/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_NAME.app"
echo "完成: $APP_NAME.app"
echo "运行: open $APP_NAME.app"
