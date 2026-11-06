#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TOOLCHAIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SDK="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
BUILD="$ROOT/.build/device"
PAYLOAD="$BUILD/Payload"
APP="$PAYLOAD/GuestBookHelper.app"
VERSION="1.8"
BUILD_NUMBER="9"
IPA="$ROOT/dist/GuestBookHelper-${VERSION}-unsigned.ipa"
TARGET="arm64-apple-ios13.0"

rm -rf "$BUILD"
mkdir -p "$APP/Frameworks" "$BUILD/modulecache" "$ROOT/dist"
find GuestBookHelper -name '*.swift' | sort > "$BUILD/sources.txt"

echo "1/6 编译 arm64 真机二进制（iOS 13+）…"
"$TOOLCHAIN/swiftc" -emit-executable -parse-as-library -swift-version 5 -O \
  -sdk "$SDK" -target "$TARGET" -module-name GuestBookHelper \
  -module-cache-path "$BUILD/modulecache" \
  -framework SwiftUI -framework UIKit -framework Foundation \
  -framework AVFoundation -framework CoreImage -framework Vision \
  -lcompression -lsqlite3 \
  -Xlinker -platform_version -Xlinker ios -Xlinker 13.0 -Xlinker 26.2 \
  -Xlinker -rpath -Xlinker "@executable_path/Frameworks" \
  -Xlinker -dead_strip \
  -o "$APP/GuestBookHelper" \
  @"$BUILD/sources.txt"

echo "2/6 编译资源目录（iPhoneOS）…"
"$DEVELOPER_DIR/usr/bin/actool" \
  --compile "$APP" \
  --platform iphoneos \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --accent-color AccentColor \
  --target-device iphone \
  --target-device ipad \
  --output-partial-info-plist "$BUILD/assets.plist" \
  --output-format human-readable-text \
  GuestBookHelper/Resources/Assets.xcassets

echo "3/6 复制资源…"
cp GuestBookHelper/Resources/PrivacyInfo.xcprivacy "$APP/PrivacyInfo.xcprivacy"
cp GuestBookHelper/Resources/LaunchImages/*.png "$APP/"
printf 'APPL????' > "$APP/PkgInfo"

# Swift concurrency back-deployment for iOS 13/14.
CONCURRENCY="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.5/iphoneos/libswift_Concurrency.dylib"
if [[ -f "$CONCURRENCY" ]]; then
  cp "$CONCURRENCY" "$APP/Frameworks/libswift_Concurrency.dylib"
fi

echo "4/6 生成 Info.plist…"
python3 - "$APP" "$BUILD/assets.plist" <<'PY'
import plistlib, sys, os
app, assets_path = sys.argv[1], sys.argv[2]
with open('GuestBookHelper/Resources/Info.plist', 'rb') as f:
    info = plistlib.load(f)
for key, value in {
    'CFBundleExecutable': 'GuestBookHelper',
    'CFBundleIdentifier': 'com.n1c0.guestbookhelper.app',
    'CFBundleName': 'GuestBookHelper',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '1.8',
    'CFBundleVersion': '9',
    'MinimumOSVersion': '13.0',
    'UIDeviceFamily': [1, 2],
    'LSRequiresIPhoneOS': True,
    'CFBundleSupportedPlatforms': ['iPhoneOS'],
    'DTPlatformName': 'iphoneos',
    'DTSDKName': 'iphoneos26.2',
    'DTPlatformVersion': '26.2',
    'DTXcode': '2620',
    'DTCompiler': 'com.apple.compilers.llvm.clang.1_0',
    'BuildMachineOSBuild': '24G824',
}.items():
    info[key] = value
if os.path.exists(assets_path):
    with open(assets_path, 'rb') as f:
        assets = plistlib.load(f)
    for key, value in assets.items():
        info[key] = value
with open(os.path.join(app, 'Info.plist'), 'wb') as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_BINARY, sort_keys=False)
PY

echo "5/6 打包未签名 IPA…"
rm -f "$IPA"
(cd "$BUILD" && /usr/bin/zip -qry -X "$IPA" Payload)
rm -f "$ROOT/dist/GuestBookHelper-${VERSION}-unsigned.ipa.sha256"
(cd "$ROOT/dist" && shasum -a 256 "$(basename "$IPA")" > "$(basename "$IPA").sha256")

echo "6/6 校验…"
"$TOOLCHAIN/lipo" -info "$APP/GuestBookHelper"
/usr/bin/vtool -show-build "$APP/GuestBookHelper" | head -8
SIZE="$(du -h "$IPA" | cut -f1)"
echo "完成：$IPA ($SIZE)"
echo "SHA256：$(cut -d' ' -f1 "$ROOT/dist/GuestBookHelper-${VERSION}-unsigned.ipa.sha256")"
