#!/usr/bin/env bash
# 第一阶段只构建 SpotifyGlassLiveActivity.appex。
# 不构建 tweak、不注入 AppGroups、不触碰 Spotify 原 WidgetExtension。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v unzip >/dev/null
command -v zip >/dev/null
command -v rg >/dev/null
IN="${1:?usage: $0 <Spotify.ipa> <out.ipa>}"
OUT="${2:?usage: $0 <Spotify.ipa> <out.ipa>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

APP_INFO="$TMP/Info.plist"
APP_PATH="Payload/Spotify.app/"
unzip -p "$IN" "${APP_PATH}Info.plist" > "$APP_INFO"
"$ROOT/scripts/build-extension.sh" "$APP_INFO" "$TMP/build"

APPEX="$TMP/build/SpotifyGlassLiveActivity.appex"
test -f "$APPEX/SpotifyGlassLiveActivity"
test -f "$APPEX/Info.plist"
unzip -l "$IN" "${APP_PATH}PlugIns/*" | rg -q "${APP_PATH}PlugIns/"

cp "$IN" "$OUT"
# 旧版目标 IPA 没有此 appex；有则仅删除同名目录，不能静默接受错误路径。
zip -qd "$OUT" "${APP_PATH}PlugIns/SpotifyGlassLiveActivity.appex/*" >/dev/null 2>&1 || true
mkdir -p "$TMP/inject/${APP_PATH}PlugIns"
cp -R "$APPEX" "$TMP/inject/${APP_PATH}PlugIns/"
(cd "$TMP/inject" && zip -qry "$OUT" "$APP_PATH")

# 必须留下目标 appex 于宿主 PlugIns，且不能意外写入主 dylib / 其他 extension。
unzip -t "$OUT" >/dev/null
unzip -l "$OUT" "${APP_PATH}PlugIns/SpotifyGlassLiveActivity.appex/SpotifyGlassLiveActivity" | rg -q "${APP_PATH}PlugIns/SpotifyGlassLiveActivity.appex/SpotifyGlassLiveActivity$"
echo "Phase 1 extension replacement ready: $OUT"
