#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
WIDGETS_DIR="$ROOT_DIR/Widgets"
SDK_DIR="$ROOT_DIR/Sources/DockDoorWidgetSDK"
SDK_OUT="$BUILD_DIR/sdk"

echo "=== DockDoor Pro Widget Builder ==="
echo ""

mkdir -p "$BUILD_DIR" "$SDK_OUT"

# Step 1: Compile SDK into a .swiftmodule so widgets can import it
echo "Building DockDoorWidgetSDK..."
for arch in arm64 x86_64; do
    mkdir -p "$SDK_OUT/$arch"
    swiftc \
        -target ${arch}-apple-macosx14.0 \
        -module-name DockDoorWidgetSDK \
        -emit-module \
        -emit-module-path "$SDK_OUT/$arch/DockDoorWidgetSDK.swiftmodule" \
        -parse-as-library \
        "$SDK_DIR"/*.swift 2>&1
done
echo "SDK built successfully."
echo ""

# Step 2: Determine which widgets to build
if [ $# -ge 1 ]; then
    WIDGET_DIRS=("$@")
else
    WIDGET_DIRS=()
    for dir in "$WIDGETS_DIR"/*/; do
        [ -d "$dir" ] && WIDGET_DIRS+=("$dir")
    done
fi

SUCCESS_COUNT=0
FAIL_COUNT=0

for WIDGET_DIR in "${WIDGET_DIRS[@]}"; do
    WIDGET_DIR="${WIDGET_DIR%/}"
    WIDGET_NAME=$(basename "$WIDGET_DIR")
    WIDGET_JSON="$WIDGET_DIR/widget.json"

    echo "--- Building: $WIDGET_NAME ---"

    if [ ! -f "$WIDGET_JSON" ]; then
        echo "  SKIP: No widget.json"
        echo ""
        continue
    fi

    # widget_rules.py validates the folder and prints the id, the principal class,
    # then one plain source filename per line.
    if ! BUILD_INFO=$(python3 "$SCRIPT_DIR/widget_rules.py" build-info "$WIDGET_DIR"); then
        echo "  FAIL: widget breaks the folder rules (see RULE lines above)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo ""
        continue
    fi

    WIDGET_ID=""
    PRINCIPAL_CLASS=""
    SOURCE_FILES=()
    LINE_NUMBER=0
    while IFS= read -r line; do
        case $LINE_NUMBER in
            0) WIDGET_ID="$line" ;;
            1) PRINCIPAL_CLASS="$line" ;;
            *) SOURCE_FILES+=("$WIDGET_DIR/$line") ;;
        esac
        LINE_NUMBER=$((LINE_NUMBER + 1))
    done <<< "$BUILD_INFO"

    echo "  ID:    $WIDGET_ID"
    echo "  Class: $PRINCIPAL_CLASS"

    BUNDLE_DIR="$BUILD_DIR/${WIDGET_NAME}.bundle"
    BUNDLE_MACOS="$BUNDLE_DIR/Contents/MacOS"

    rm -rf "$BUNDLE_DIR"
    mkdir -p "$BUNDLE_MACOS"

    # Compile for each architecture, then merge into a universal binary
    echo "  Compiling..."
    for arch in arm64 x86_64; do
        swiftc \
            -target ${arch}-apple-macosx14.0 \
            -emit-library \
            -o "$BUNDLE_MACOS/${WIDGET_NAME}_${arch}" \
            -module-name "$WIDGET_NAME" \
            -I "$SDK_OUT/$arch" \
            -Xlinker -undefined -Xlinker dynamic_lookup \
            "${SOURCE_FILES[@]}" 2>&1
    done
    lipo -create \
        "$BUNDLE_MACOS/${WIDGET_NAME}_arm64" \
        "$BUNDLE_MACOS/${WIDGET_NAME}_x86_64" \
        -output "$BUNDLE_MACOS/$WIDGET_NAME"
    rm "$BUNDLE_MACOS/${WIDGET_NAME}_arm64" "$BUNDLE_MACOS/${WIDGET_NAME}_x86_64"

    cat > "$BUNDLE_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${WIDGET_ID}</string>
    <key>CFBundleName</key>
    <string>${WIDGET_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${WIDGET_NAME}</string>
    <key>NSPrincipalClass</key>
    <string>${PRINCIPAL_CLASS}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
</dict>
</plist>
PLIST

    cd "$BUILD_DIR"
    zip -qr "${WIDGET_NAME}.bundle.zip" "${WIDGET_NAME}.bundle"
    cd "$ROOT_DIR"

    echo "  SUCCESS: $BUNDLE_DIR"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    echo ""
done

echo "=== Build Complete ==="
echo "  Succeeded: $SUCCESS_COUNT"
echo "  Failed:    $FAIL_COUNT"
echo "  Output:    $BUILD_DIR/"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
