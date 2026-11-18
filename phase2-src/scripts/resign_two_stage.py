#!/usr/bin/env python3
"""两段式签名：只改 SpotifyGlassLiveActivity.appex 的 application-identifier 为真实 bundle id，
其余 appex 保持描述文件 App ID。这样灵动岛点击关联回 Spotify，不跳"读txt"。"""
import glob, os, plistlib, shutil, subprocess, sys, tempfile, zipfile

KEYS = os.path.expanduser("~/.ios-signer/keys")
P12 = os.path.join(KEYS, "dev.legacy.p12")
PROFILE = os.path.join(KEYS, "dev.mobileprovision")
PASSFILE = os.path.join(KEYS, "p12.pass")

ipa = os.path.abspath(sys.argv[1])
out = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.splitext(ipa)[0] + "-signed.ipa"

with open(PASSFILE) as f:
    password = f.read().strip()

# 描述文件 team + appex 真实 bundle id
raw = subprocess.run(["openssl", "smime", "-inform", "DER", "-verify", "-noverify", "-in", PROFILE],
                     capture_output=True).stdout
prov = plistlib.loads(raw)
team = prov["TeamIdentifier"][0]
prov_ent = dict(prov["Entitlements"])

work = tempfile.mkdtemp(prefix="resign2-")
try:
    with zipfile.ZipFile(ipa) as z:
        z.extractall(work)
    app = glob.glob(os.path.join(work, "Payload", "*.app"))[0]

    # copyfile 描述文件到主 App + 所有 appex
    shutil.copyfile(PROFILE, os.path.join(app, "embedded.mobileprovision"))
    appexes = glob.glob(os.path.join(app, "PlugIns", "*.appex"))
    for appex in appexes:
        shutil.copyfile(PROFILE, os.path.join(appex, "embedded.mobileprovision"))

    # 清旧签名
    for cs in glob.glob(os.path.join(app, "**", "_CodeSignature"), recursive=True):
        shutil.rmtree(cs, ignore_errors=True)

    # 1) zsign -f 就地签整个 Payload（application-identifier 统一 = 描述文件 App ID）
    r = subprocess.run(["/usr/local/bin/zsign", "-f", "-k", P12, "-p", password, "-m", PROFILE, "-L", "."],
                       cwd=work, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"❌ 递归签失败:\n{(r.stdout+r.stderr)[-600:]}")

    # 2) zsign -e 只改 SpotifyGlassLiveActivity.appex 的 application-identifier
    target = os.path.join(app, "PlugIns", "SpotifyGlassLiveActivity.appex")
    with open(os.path.join(target, "Info.plist"), "rb") as f:
        appex_bid = plistlib.load(f)["CFBundleIdentifier"]
    ent = dict(prov_ent)
    ent["application-identifier"] = f"{team}.{appex_bid}"
    ent_path = os.path.join(work, "appex-ent.plist")
    with open(ent_path, "wb") as f:
        plistlib.dump(ent, f)
    r2 = subprocess.run(["/usr/local/bin/zsign", "-f", "-k", P12, "-p", password, "-m", PROFILE,
                         "-e", ent_path, target],
                        capture_output=True, text=True)
    if r2.returncode != 0:
        sys.exit(f"❌ appex 重签失败:\n{(r2.stdout+r2.stderr)[-600:]}")

    # 3) zsign -o 打包（DEFLATE，读缓存跳过已签 appex）
    os.path.exists(out) and os.remove(out)
    r3 = subprocess.run(["/usr/local/bin/zsign", "-k", P12, "-p", password, "-m", PROFILE,
                         "-L", "-o", out, "-z", "9", "."],
                        cwd=work, capture_output=True, text=True)
    print(r3.stdout[-400:] if r3.returncode == 0 else f"❌ 打包失败:\n{(r3.stdout+r3.stderr)[-600:]}")
    if r3.returncode != 0 or not os.path.exists(out):
        sys.exit(1)
    print(f"📦 {out} ({os.path.getsize(out)} 字节)")
finally:
    shutil.rmtree(work, ignore_errors=True)
