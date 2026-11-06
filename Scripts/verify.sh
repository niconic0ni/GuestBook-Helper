#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TOOLCHAIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SDK="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
BUILD="$ROOT/.build/verification"
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  TARGET="arm64-apple-macos14.0"
else
  TARGET="x86_64-apple-macos14.0"
fi

mkdir -p "$BUILD"
echo "编译校验程序（macOS，Foundation + SQLite + Compression）…"
"$TOOLCHAIN/swiftc" -O -swift-version 5 -sdk "$SDK" -target "$TARGET" \
  -module-cache-path "$ROOT/.build/modulecache" \
  -lcompression -lsqlite3 \
  -o "$BUILD/GuestBookHelperVerify" \
  GuestBookHelper/Models/InventoryModels.swift \
  GuestBookHelper/Models/Formatters.swift \
  GuestBookHelper/Services/ZipArchive.swift \
  GuestBookHelper/Services/XLSXWorkbook.swift \
  GuestBookHelper/Services/XLSXInventoryParser.swift \
  GuestBookHelper/Services/StoreDatabase.swift \
  GuestBookHelper/Services/DatabaseStore.swift \
  GuestBookHelper/Services/InventoryImporter.swift \
  GuestBookHelper/Services/LogXLSXExporter.swift \
  Scripts/verify/main.swift

echo "检查 Info.plist 的系统分享关联…"
DOCUMENT_TYPES="$(plutil -extract CFBundleDocumentTypes json -o - GuestBookHelper/Resources/Info.plist)"
echo "$DOCUMENT_TYPES" | grep -q "org.openxmlformats.spreadsheetml.sheet"
echo "$DOCUMENT_TYPES" | grep -q "xlsx"
plutil -extract LSSupportsOpeningDocumentsInPlace raw -o - GuestBookHelper/Resources/Info.plist | grep -q "true"
plutil -extract NSCameraUsageDescription raw -o - GuestBookHelper/Resources/Info.plist | grep -q "条码"
echo "   xlsx → GuestBook Helper 文档关联已注册"
echo "   相机权限说明已注册"

echo "运行数据与导入校验…"
"$BUILD/GuestBookHelperVerify" | tee "$BUILD/verification.log"
echo "校验通过。"
