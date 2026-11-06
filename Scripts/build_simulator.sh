#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TOOLCHAIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SDK="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
BUILD="$ROOT/.build/simulator"
APP="$BUILD/GuestBookHelper.app"
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  TARGET="arm64-apple-ios13.0-simulator"
else
  TARGET="x86_64-apple-ios13.0-simulator"
fi

rm -rf "$BUILD"
mkdir -p "$APP" "$BUILD/modulecache"
find GuestBookHelper -name '*.swift' | sort > "$BUILD/sources.txt"

echo "编译 Swift（iOS 13+，模拟器）…"
"$TOOLCHAIN/swiftc" -emit-executable -parse-as-library -swift-version 5 -O \
  -sdk "$SDK" -target "$TARGET" -module-name GuestBookHelper -D DEBUG \
  -module-cache-path "$BUILD/modulecache" \
  -framework SwiftUI -framework UIKit -framework Foundation \
  -framework AVFoundation -framework CoreImage -framework Vision \
  -lcompression -lsqlite3 \
  -Xlinker -platform_version -Xlinker ios-simulator -Xlinker 13.0 -Xlinker 26.2 \
  -o "$APP/GuestBookHelper" \
  @"$BUILD/sources.txt"

echo "编译资源目录…"
"$DEVELOPER_DIR/usr/bin/actool" \
  --compile "$APP" \
  --platform iphonesimulator \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --accent-color AccentColor \
  --output-partial-info-plist "$BUILD/assets.plist" \
  --output-format human-readable-text \
  GuestBookHelper/Resources/Assets.xcassets

cp GuestBookHelper/Resources/PrivacyInfo.xcprivacy "$APP/PrivacyInfo.xcprivacy"
cp GuestBookHelper/Resources/LaunchImages/*.png "$APP/"
printf 'APPL????' > "$APP/PkgInfo"

echo "生成 Info.plist…"
python3 - "$APP" "$BUILD/assets.plist" <<'PY'
import plistlib, sys, os, datetime
app, assets_path = sys.argv[1], sys.argv[2]
src = 'GuestBookHelper/Resources/Info.plist'
with open(src, 'rb') as f:
    info = plistlib.load(f)
for k, v in {
    'CFBundleExecutable':'GuestBookHelper',
    'CFBundleIdentifier':'com.n1c0.guestbookhelper.app',
    'CFBundleName':'GuestBookHelper',
    'CFBundlePackageType':'APPL',
    'CFBundleShortVersionString':'1.8',
    'CFBundleVersion':'9',
    'MinimumOSVersion':'13.0',
    'UIDeviceFamily':[1, 2],
    'LSRequiresIPhoneOS':True,
    'CFBundleSupportedPlatforms':['iPhoneSimulator'],
    'DTPlatformName':'iphonesimulator',
    'DTSDKName':'iphonesimulator26.2',
    'DTPlatformVersion':'26.2',
    'DTXcode':'2620',
    'DTCompiler':'com.apple.compilers.llvm.clang.1_0',
    'BuildMachineOSBuild':'24G824',
}.items():
    info[k] = v
info['UILaunchScreen'] = {'UIColorName': 'LaunchBackground', 'UIImageName': 'LaunchMark'}
if os.path.exists(assets_path):
    with open(assets_path, 'rb') as f:
        assets = plistlib.load(f)
    for k, v in assets.items():
        info[k] = v
with open(os.path.join(app, 'Info.plist'), 'wb') as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_BINARY, sort_keys=False)
PY

echo "签名（模拟器 ad-hoc）…"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "完成：$APP"
