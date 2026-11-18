#!/bin/sh
# SpotifyGlass 同步并构建：版本号自动递增 + 同步源码到公库 + 触发 GitHub Actions 构建。
set -e

SRC=/var/minis/workspace/spotifyglass-phase2
PUB=/var/minis/workspace/llama-ios-build

# 1. 版本号递增：0.23.0-beta-r1 -> r2 -> r3 ...
BUILD=$(cat "$SRC/build.txt")
BUILD=$((BUILD + 1))
printf '%d\n' "$BUILD" > "$SRC/build.txt"
printf '0.23.0-beta-r%d\n' "$BUILD" > "$SRC/version.txt"
echo "📦 版本: 0.23.0-beta-r$BUILD"

# 2. 同步源码到公库输入目录
rm -rf "$PUB/phase2-src"
mkdir -p "$PUB/phase2-src"
cp -R "$SRC/tweak" "$SRC/extension" "$SRC/vendor" "$SRC/scripts" "$PUB/phase2-src/"
cp "$SRC/version.txt" "$PUB/phase2-src/version.txt"
rm -rf "$PUB/phase2-src/tweak/.theos" \
       "$PUB/phase2-src/tweak/packages" \
       "$PUB/phase2-src/dist" \
       "$PUB/phase2-src/tweak/Sources/Shared/Flags/SGFlagList.m" \
       "$PUB/phase2-src/vendor/com.hopeless.autoflex_0.0.1_iphoneos-arm.deb" \
       "$PUB/phase2-src/scripts/__pycache__"

# 3. 提交推送公库
cd "$PUB"
git add -A
git commit -m "build: SpotifyGlass r$BUILD" -q
git push origin main

# 4. 触发 macOS 构建
gh workflow run spotifyglass-phase2.yml --repo mickeu/llama-ios-build --ref main
echo "✅ 已触发构建 0.23.0-beta-r$BUILD"
