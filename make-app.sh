#!/bin/zsh
# Openly.app 构建脚本：release 编译 → 组装 .app bundle → 本地签名
# 用法：./make-app.sh [输出目录，默认 ./dist]
# 版本号：优先取环境变量 OPENLY_VERSION，否则取最近一个 git tag（去掉前缀 v）

set -euo pipefail
cd "$(dirname "$0")"

OUT_DIR="${1:-dist}"
APP_NAME="Openly"
BUNDLE_ID="cn.openly.app"
# 没有 git 仓库、或仓库里还没有 tag 时，git describe 返回非零；pipefail 下会让
# 赋值整句失败并触发 set -e，所以这里显式兜住
VERSION="${OPENLY_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"

echo "── 1/4 release 编译…"
# --disable-sandbox：SwiftPM 自带的构建沙箱在部分受限环境（CI / 受管沙箱）无法启用
swift build -c release --disable-sandbox --product Openly
BIN=".build/release/$APP_NAME"
[[ -x "$BIN" ]] || { echo "   ✗ 未找到可执行文件：$BIN"; exit 1; }

echo "── 2/4 组装 $APP_NAME.app…"
APP="$OUT_DIR/$APP_NAME.app"
mkdir -p "$OUT_DIR"
# 输出目录打个「别索引」标记：.app 放在仓库里时 Spotlight 会把它当成一份装好的
# 应用，于是「应用程序」里除了 /Applications 那一个，还多出一个构建产物。
: > "$OUT_DIR/.metadata_never_index"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

ICON="Assets/AppIcon.icns"
[[ -f "$ICON" ]] && cp "$ICON" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticTermination</key> <false/>
    <key>NSSupportsSuddenTermination</key>   <false/>
</dict>
</plist>
PLIST

if [[ -f "$ICON" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null
fi

echo "── 3/4 签名…"
# 优先级：OPENLY_SIGN_IDENTITY 显式指定（make-dmg.sh 传 "-" 强制 ad-hoc，用于
# 对外分发）> 机器上第一枚可用证书（本机自用）> ad-hoc 兜底。
IDENTITY="${OPENLY_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"[^"]+"' | head -1 | tr -d '"') || true
fi
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP" >/dev/null 2>&1 \
        || codesign --force --sign "$IDENTITY" "$APP"
    echo "   已用 $IDENTITY 签名"
else
    codesign --force --sign - "$APP"
    echo "   ad-hoc 签名"
fi

echo "── 4/4 校验…"
codesign --verify --verbose "$APP" 2>&1 | tail -1
spctl --assess --type execute "$APP" 2>&1 || true

echo ""
echo "✓ 完成：$APP（版本 $VERSION）"
