#!/usr/bin/env python3
"""Verify a phase-2 SpotifyGlass IPA against its original Spotify IPA."""
import hashlib
import plistlib
import sys
import zipfile

if len(sys.argv) != 3:
    raise SystemExit(f"usage: {sys.argv[0]} <original.ipa> <phase2.ipa>")

original, built = map(zipfile.ZipFile, sys.argv[1:])

def app_root(z):
    marker = '/Info.plist'
    roots = sorted({n[:-len(marker)] for n in z.namelist()
                    if n.startswith('Payload/') and n.endswith(marker) and n.count('/') == 2 and n.split('/')[1].endswith('.app')})
    if len(roots) != 1:
        raise SystemExit(f"expected one app root, got {roots}")
    return roots[0] + '/'

def digest(z, name):
    return hashlib.sha256(z.read(name)).hexdigest()

root_a, root_b = app_root(original), app_root(built)
if root_a != root_b:
    raise SystemExit(f"app root changed: {root_a} -> {root_b}")
root = root_a
old_names, new_names = set(original.namelist()), set(built.namelist())
old_dylibs = sorted(n for n in old_names if n.startswith(root + 'Frameworks/') and n.rsplit('/', 1)[-1].startswith('spotifyglass') and n.endswith('.dylib'))
new_dylibs = sorted(n for n in new_names if n.startswith(root + 'Frameworks/') and n.rsplit('/', 1)[-1].startswith('spotifyglass') and n.endswith('.dylib'))
if len(old_dylibs) != 1 or new_dylibs != old_dylibs:
    raise SystemExit(f"spotifyglass dylib invariant failed: old={old_dylibs}, new={new_dylibs}")
allowed_prefixes = {old_dylibs[0], root + 'PlugIns/SpotifyGlassLiveActivity.appex/', root + 'Metadata.appintents/', root + 'Info.plist'}
for name in sorted(old_names | new_names):
    if name.endswith('/'):
        continue
    allowed = any(name == p or name.startswith(p) for p in allowed_prefixes)
    if name not in old_names:
        if not allowed:
            raise SystemExit(f"unexpected added file: {name}")
        continue
    if name not in new_names:
        if not allowed:
            raise SystemExit(f"unexpected removed file: {name}")
        continue
    if not allowed and digest(original, name) != digest(built, name):
        raise SystemExit(f"unexpected changed file: {name}")
info_a = plistlib.loads(original.read(root + 'Info.plist'))
info_b = plistlib.loads(built.read(root + 'Info.plist'))
# 只允许新增 NSSupportsLiveActivities=true，其余字段必须与原始一致。
info_b_without = dict(info_b)
info_b_without.pop('NSSupportsLiveActivities', None)
if info_b_without != info_a or info_b.get('NSSupportsLiveActivities') is not True:
    raise SystemExit("Info.plist changed beyond NSSupportsLiveActivities=true")
a = info_a.get('CFBundleIcons', {}).get('CFBundleAlternateIcons', {})
b = info_b.get('CFBundleIcons', {}).get('CFBundleAlternateIcons', {})
if a != b or len(a) != 34:
    raise SystemExit(f"alternate icon plist changed: {len(a)} -> {len(b)}")
for key, value in a.items():
    for stem in value.get('CFBundleIconFiles', [])[:1]:
        target = root + stem + '@3x.png'
        if target not in new_names or digest(original, target) != digest(built, target):
            raise SystemExit(f"icon asset changed or missing: {key} {target}")
widget = root + 'PlugIns/WidgetExtension.appex/'
for name in old_names:
    if name.startswith(widget) and not name.endswith('/') and name in new_names and digest(original, name) != digest(built, name):
        raise SystemExit(f"original WidgetExtension changed: {name}")
appex = root + 'PlugIns/SpotifyGlassLiveActivity.appex/SpotifyGlassLiveActivity'
if appex not in new_names:
    raise SystemExit('SpotifyGlassLiveActivity.appex binary missing')
old_appex_entries = {n for n in old_names if n.startswith(root + 'PlugIns/SpotifyGlassLiveActivity.appex/')}
if old_appex_entries and any(n not in new_names for n in old_appex_entries):
    raise SystemExit('existing SpotifyGlassLiveActivity.appex was partially removed')
print('phase2 IPA verified')
print('host dylib:', old_dylibs[0])
print('appex:', appex)
print('alternate icons:', len(a))
print('host dylib sha256:', digest(built, old_dylibs[0]))
print('appex sha256:', digest(built, appex))
