#!/bin/zsh
# 打包对外分发的 DMG：Openly.app + /Applications 快捷方式。
# 用法：./make-dmg.sh
#
# 签名策略（对外分发）：默认 ad-hoc（codesign --sign -）。
# 本仓库没有 Developer ID Application 证书，无法公证；Apple Development 签名
# 对陌生机器同样过不了 Gatekeeper，还会带上 get-task-allow 调试 entitlement，
# 对外分发是更差的产物。需要 Developer ID 签名时：
#   OPENLY_SIGN_IDENTITY="Developer ID Application: …" ./make-dmg.sh
#
# 新机器首次打开被 Gatekeeper 拦截属预期行为，引导见 README「安装」一节。

set -euo pipefail
cd "$(dirname "$0")"

# 没有 git 仓库、或仓库里还没有 tag 时，git describe 返回非零；pipefail 下会让
# 赋值整句失败并触发 set -e，所以这里显式兜住
VERSION="${OPENLY_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
DMG="dist/Openly-$VERSION.dmg"

# 组装过程放临时目录：dist/ 只留一个 dmg。
# 把 Openly.app 直接建在 dist/ 下时，Spotlight 会把仓库里的构建产物也收进
# 「应用程序」，于是列表里出现两个 Openly。
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/openly-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/app/Openly.app"
IMAGE="$STAGING/image"

mkdir -p dist
# 兜底：即使以后有人往 dist/ 里丢了个 .app，这个标记也会让 Spotlight 整棵跳过。
: > dist/.metadata_never_index

APP_SIGN_IDENTITY="${OPENLY_SIGN_IDENTITY:--}"

echo "── 1/4 构建 Openly.app…"
OPENLY_VERSION="$VERSION" OPENLY_SIGN_IDENTITY="$APP_SIGN_IDENTITY" ./make-app.sh "$STAGING/app"

echo "── 2/4 组装 DMG 内容…"
mkdir -p "$IMAGE"
cp -R "$APP" "$IMAGE/"
ln -s /Applications "$IMAGE/Applications"

echo "── 3/4 压缩为 DMG…"
rm -f "$DMG"
hdiutil create -volname "Openly" \
    -srcfolder "$IMAGE" \
    -fs HFS+ \
    -ov -format UDZO -imagekey zlib-level=9 \
    "$DMG" >/dev/null

echo "── 4/4 签名与校验…"
codesign --sign "$APP_SIGN_IDENTITY" "$DMG"
hdiutil verify "$DMG" >/dev/null && echo "   hdiutil verify 通过"

echo ""
echo "✓ 完成：$DMG"
echo "  dist/ 里只有这一个文件（.app 是临时目录里拼的，装完就没了）。"
echo ""
echo "⚠ 分发提示：本仓库无 Developer ID 证书，产物为 ad-hoc 签名、未公证。"
echo "  新机器首次打开会被 Gatekeeper 拦截（macOS 15+ 已无法用「右键 → 打开」绕过）："
echo "    · 系统设置 › 隐私与安全性 › 仍要打开"
echo "    · 或：xattr -cr /Applications/Openly.app"
echo "  完整引导见 README「安装」一节。"
