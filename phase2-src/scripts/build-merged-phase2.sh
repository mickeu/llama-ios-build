#!/usr/bin/env bash
# 合并阶段 2：唯一 spotifyglass dylib + 唯一 Live Activity appex。
# 不注入 FLEX / App Group shim；不触碰 Spotify 原 WidgetExtension；不运行 app-icons.sh。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IN="${1:?usage: $0 <decrypted Spotify.ipa> <output unsigned.ipa>}"
OUT="${2:?usage: $0 <decrypted Spotify.ipa> <output unsigned.ipa>}"
for cmd in unzip zip plutil xcrun gmake ldid python3 sha256sum rg dpkg-deb; do command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 1; }; done
[ -f "$IN" ] || { echo "input IPA missing" >&2; exit 1; }
APP="$(unzip -Z1 "$IN" | rg '^Payload/[^/]+\.app/Info\.plist$' | head -1 | sed 's|Info.plist$||')"
[ -n "$APP" ] || { echo "no Payload app" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -q "$IN" -d "$TMP"
APPDIR="$TMP/${APP%/}"
[ -d "$APPDIR/Frameworks" ] || { echo "Frameworks missing" >&2; exit 1; }
[ -d "$APPDIR/PlugIns" ] || { echo "PlugIns missing" >&2; exit 1; }
[ -f "$APPDIR/Info.plist" ] || { echo "Info.plist missing" >&2; exit 1; }

# 输入 IPA 的当前 34 个图标必须原样存在，构建流程不生成/覆盖它们。
python3 - "$APPDIR/Info.plist" <<'PY'
import plistlib, sys
p=plistlib.load(open(sys.argv[1],'rb'))
a=p.get('CFBundleIcons',{}).get('CFBundleAlternateIcons',{})
if len(a) < 2: raise SystemExit('alternate icon set missing')
print(f'alternate icons preserved: {len(a)}')
PY

# 先构建唯一 host dylib；其产物必须由 Theos package 生成。
# 清理损坏/中断构建留下的对象，避免把污染物带入最终链接。
export THEOS="${THEOS:?THEOS must point to a configured Theos tree}"
BAD_OBJECTS="$(rg --files -uuu "$ROOT/tweak/.theos" 2>/dev/null | rg '/(.*\.o\.tmp|.*\.tmp|core|\.DS_Store)$|/[^/]+\.o$' || true)"
if [ -n "$BAD_OBJECTS" ]; then
  printf '%s\n' "prebuild cleanup:" "$BAD_OBJECTS"
  while IFS= read -r object; do rm -f "$object"; done <<< "$BAD_OBJECTS"
fi
mkdir -p "$ROOT/dist"
if ! gmake -C "$ROOT/tweak" clean package >"$ROOT/dist/phase2-host-build.log" 2>&1; then
  tail -120 "$ROOT/dist/phase2-host-build.log" >&2
  exit 1
fi
DEB="$(ls -t "$ROOT"/tweak/packages/*.deb | head -1)"
[ -f "$DEB" ] || { echo "tweak deb missing" >&2; exit 1; }

# Theos deb 中的唯一 dylib，路径由 package 结构验证后抽取。
mkdir -p "$TMP/deb"; dpkg-deb -x "$DEB" "$TMP/deb"
DYLIB="$(rg --files "$TMP/deb" | rg '/spotifyglass\.dylib$' | head -1)"
[ -n "$DYLIB" ] || { echo "spotifyglass dylib missing from deb" >&2; exit 1; }
OLD_DYLIB="$(rg --files "$APPDIR/Frameworks" | rg '/spotifyglass.*\.dylib$')"
[ "$(printf '%s\n' "$OLD_DYLIB" | wc -l | tr -d ' ')" -eq 1 ] || { echo "expected exactly one existing spotifyglass dylib" >&2; exit 1; }
cp "$DYLIB" "$OLD_DYLIB"

# 同源码的 shared ContentState 构建 appex；只替换这一项。
EXT="$TMP/ext"
"$ROOT/scripts/build-extension.sh" "$APPDIR/Info.plist" "$EXT"
APPEX="$EXT/SpotifyGlassLiveActivity.appex"
[ -f "$APPEX/SpotifyGlassLiveActivity" ] || { echo "appex binary missing" >&2; exit 1; }
rm -rf "$APPDIR/PlugIns/SpotifyGlassLiveActivity.appex"
cp -R "$APPEX" "$APPDIR/PlugIns/SpotifyGlassLiveActivity.appex"

# 先以当前解包树重打未签 IPA，再原地合并 Live Activity App Intents metadata。
# 不改 Spotify 主可执行文件或原 WidgetExtension。
(cd "$TMP" && zip -qry "$OUT" Payload -x '*.DS_Store')
"$ROOT/scripts/merge-appintents.py" "$OUT" "$APP" "$EXT/app/Metadata.appintents"
unzip -tq "$OUT" >/dev/null
python3 "$ROOT/scripts/verify_phase2_ipa.py" "$IN" "$OUT"
sha256sum "$OUT"
