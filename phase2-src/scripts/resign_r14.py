#!/usr/bin/env python3
"""签 r14：跳过 rcodesign preflight（Spotify 二进制 rcodesign 解析不了，但 zsign 能签）。
按技能库 resign_keep_bundleid.py 的正确流程：copyfile 描述文件 + 清旧签名 + zsign -o 打包。"""
import glob, os, plistlib, shutil, subprocess, sys, tempfile, zipfile

KEYS = os.path.expanduser("~/.ios-signer/keys")
P12 = os.path.join(KEYS, "dev.legacy.p12")
PROFILE = os.path.join(KEYS, "dev.mobileprovision")
PASSFILE = os.path.join(KEYS, "p12.pass")

ipa = os.path.abspath(sys.argv[1])
out = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.splitext(ipa)[0] + "-signed.ipa"

with open(PASSFILE) as f:
    password = f.read().strip()

work = tempfile.mkdtemp(prefix="resign-")
try:
    with zipfile.ZipFile(ipa) as z:
        z.extractall(work)
    app = glob.glob(os.path.join(work, "Payload", "*.app"))[0]

    with open(os.path.join(app, "Info.plist"), "rb") as f:
        bid = plistlib.load(f).get("CFBundleIdentifier")
    print(f"✅ 保留原包名: {bid}")

    # copyfile 描述文件到主 App + 所有 appex
    shutil.copyfile(PROFILE, os.path.join(app, "embedded.mobileprovision"))
    appexes = glob.glob(os.path.join(app, "PlugIns", "*.appex"))
    for appex in appexes:
        shutil.copyfile(PROFILE, os.path.join(appex, "embedded.mobileprovision"))
    print(f"✅ 描述文件已塞入主 App + {len(appexes)} 个 appex")

    # 清旧签名
    for cs in glob.glob(os.path.join(app, "**", "_CodeSignature"), recursive=True):
        shutil.rmtree(cs, ignore_errors=True)

    # zsign -o 打包（原版 zsign，application-identifier 用描述文件 App ID）
    os.path.exists(out) and os.remove(out)
    r = subprocess.run(["/usr/local/bin/zsign", "-k", P12, "-p", password, "-m", PROFILE,
                        "-L", "-o", out, "-z", "9", "."],
                       cwd=work, capture_output=True, text=True)
    print(r.stdout[-500:] if r.returncode == 0 else f"❌ zsign 失败:\n{(r.stdout+r.stderr)[-800:]}")
    if r.returncode != 0 or not os.path.exists(out):
        sys.exit(1)
    print(f"📦 {out} ({os.path.getsize(out)} 字节)")
finally:
    shutil.rmtree(work, ignore_errors=True)
