#!/usr/bin/env python3
"""
resign_keep_bundleid.py — 保持原包名的 iOS 重签（复现 LCSign / 轻松签 / 全能签 的能力）

用法:
    python3 resign_keep_bundleid.py <input.ipa> [output.ipa]
    python3 resign_keep_bundleid.py <input.ipa> --install      # 签完直接装

原理（关键，别再搞错）:
    1. **保留 App 原 CFBundleIdentifier，绝不改包名**
    2. 只把签名 entitlements 设为描述文件的 Entitlements（application-identifier = <team>.<profileAppID>）
    3. 用 p12 签名
    → iOS 安装校验的是 entitlements（匹配描述文件 ✅），系统按 CFBundleIdentifier 区分 App
    → 因此一份描述文件可签任意包名的 App，且各 App 保持原包名、互不覆盖

    ⚠️ 常见错误 1：把 CFBundleIdentifier 改成描述文件的 App ID 去"迁就"它 → 撞同一 ID 互相覆盖。
       正确做法是改 entitlements，不是改包名。
    ⚠️ 常见错误 2：以为「显式 App ID 描述文件签不了 appex」而去删扩展。错的——实测可签
       （主 App bundle 任意、appex 各自 bundle id 都过）。真正签不了的原因八成是二进制被改坏了。
    ⚠️ 常见错误 3：用 rcodesign 签带 appex / 被 patch 过的二进制 → rcodesign 对 Mach-O 容错极差，
       任何偏移错位都直接 `binary parsing error: type is too big`。本脚本默认走 zsign（原生递归签 appex）。

签名工具分工:
    zsign    原生递归签 PlugIns/appex，能 realloc CodeSignature 空间，容错好 → 默认
    rcodesign 干净输入可用，但二进制一有损坏就崩解析 → 仅作 zsign 缺失时兜底
"""
import glob
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

KEYS = os.path.expanduser("~/.ios-signer/keys")
P12 = os.path.join(KEYS, "dev.legacy.p12")           # legacy 格式（rcodesign 0.29 读得了）
PROFILE = os.path.join(KEYS, "dev.mobileprovision")  # 描述文件
PASSFILE = os.path.join(KEYS, "p12.pass")            # 密码（600）
TEAM_GROUP = "group.W98A28M8HV.DF7vj"                 # 本机描述文件里的 App Group


def macho_files(app):
    """列出 bundle 内所有 Mach-O（主二进制 + appex + framework），用于预检。"""
    out = []
    root_bin = os.path.join(app, os.path.basename(app)[:-4])
    if os.path.isfile(root_bin):
        out.append(root_bin)
    for pat in ("PlugIns/*.appex", "Frameworks/*.framework", "Watch/*.app"):
        for d in glob.glob(os.path.join(app, pat)):
            name = os.path.basename(d)
            name = name[:-6] if name.endswith(".appex") else name[:-10] if name.endswith(".framework") else name[:-4]
            b = os.path.join(d, name)
            if os.path.isfile(b):
                out.append(b)
    return out


def preflight(bins):
    """用 rcodesign 解析每个 Mach-O：解析失败 = 二进制损坏（多半是 patch 改变了文件长度）。"""
    bad = []
    for b in bins:
        r = subprocess.run(["rcodesign", "print-signature-info", b],
                           capture_output=True, text=True)
        if r.returncode != 0:
            bad.append((b, (r.stderr or r.stdout).strip().splitlines()[-1:] or [""]))
    if bad:
        print("❌ 以下 Mach-O 无法解析（文件已损坏，通常是把字符串改短导致偏移错位）:")
        for b, err in bad:
            print(f"   {os.path.relpath(b)} :: {err[0][:120]}")
        print("   修法：改用等长替换 —— new + b'\\x00' * (len(old) - len(new))，并用 ls -l 校验大小不变。")
        print("   参考 scripts/patch_binary_string.py")
        sys.exit(2)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    do_install = "--install" in sys.argv
    skip_rcodesign_preflight = "--skip-rcodesign-preflight" in sys.argv
    if not args:
        print(__doc__)
        sys.exit(1)
    ipa = os.path.abspath(args[0])
    out = os.path.abspath(args[1]) if len(args) > 1 else os.path.splitext(ipa)[0] + "-signed.ipa"
    for f in (P12, PROFILE, PASSFILE):
        if not os.path.exists(f):
            sys.exit(f"❌ 缺少签名资产: {f}")

    work = tempfile.mkdtemp(prefix="resign-")
    with zipfile.ZipFile(ipa) as z:
        z.extractall(work)
    apps = glob.glob(os.path.join(work, "Payload", "*.app"))
    if not apps:
        sys.exit("❌ IPA 里找不到 Payload/*.app")
    app = apps[0]

    # 0) zsign 可递归重签部分 rcodesign 无法解析的原始 IPA；该开关只跳过解析预检。
    if skip_rcodesign_preflight:
        if not shutil.which("zsign"):
            sys.exit("❌ --skip-rcodesign-preflight 只允许 zsign 可用时使用")
        print("⚠️ 跳过 rcodesign 解析预检，后续仍由 zsign 递归签名与 IPA 校验兜底")
    else:
        preflight(macho_files(app))

    # 1) 原包名保留
    with open(os.path.join(app, "Info.plist"), "rb") as f:
        bid = plistlib.load(f).get("CFBundleIdentifier")
    print(f"✅ 保留原包名: {bid}")

    # 2) 塞入描述文件（主 App + 所有扩展）
    shutil.copyfile(PROFILE, os.path.join(app, "embedded.mobileprovision"))
    appexes = glob.glob(os.path.join(app, "PlugIns", "*.appex"))
    for appex in appexes:
        shutil.copyfile(PROFILE, os.path.join(appex, "embedded.mobileprovision"))

    # 3) 清旧签名
    for cs in glob.glob(os.path.join(app, "**", "_CodeSignature"), recursive=True):
        shutil.rmtree(cs, ignore_errors=True)

    with open(PASSFILE) as f:
        password = f.read().strip()

    # 4) 签名：zsign 优先（原生递归签 appex），rcodesign 兜底
    os.path.exists(out) and os.remove(out)
    zsign = shutil.which("zsign")
    if zsign:
        # 注意：输入必须是「.」（含 Payload 的目录）；传 Payload/X.app 会 Signed OK 但不打包
        r = subprocess.run([zsign, "-k", P12, "-p", password, "-m", PROFILE,
                            "-L", "-o", out, "-z", "9", "."],
                           cwd=work, capture_output=True, text=True)
        if r.returncode == 0 and os.path.exists(out):
            print(f"✅ zsign 签名完成（含 {len(appexes)} 个扩展）")
        else:
            sys.exit(f"❌ zsign 签名失败:\n{(r.stdout + r.stderr)[-800:]}")
    else:
        raw = subprocess.run(
            ["openssl", "smime", "-inform", "DER", "-verify", "-noverify", "-in", PROFILE],
            capture_output=True).stdout
        ent = plistlib.loads(raw)["Entitlements"]
        ent["com.apple.security.application-groups"] = [TEAM_GROUP]
        ent_path = os.path.join(work, "ent.plist")
        with open(ent_path, "wb") as f:
            plistlib.dump(ent, f)
        print(f"⚠️ 未找到 zsign，用 rcodesign（appex 可能签不全）")
        print(f"✅ entitlements application-identifier: {ent.get('application-identifier')}")
        pw = os.path.join(work, ".pw")
        with open(pw, "w") as f:
            f.write(password)
        os.chmod(pw, 0o600)
        r = subprocess.run(
            ["rcodesign", "sign", "--p12-file", P12, "--p12-password-file", pw,
             "--entitlements-xml-file", ent_path, "--timestamp-url", "none", app],
            capture_output=True, text=True)
        os.remove(pw)
        if r.returncode != 0:
            sys.exit(f"❌ 签名失败:\n{r.stderr[-800:]}")
        subprocess.run(["zip", "-qry", out, "Payload"], cwd=work, check=True)

    print(f"📦 {out}")

    # 5) 可选安装
    if do_install:
        here = os.path.dirname(os.path.abspath(__file__))
        env = dict(os.environ, CDTK_PAIRING_FILE=os.environ.get(
            "CDTK_PAIRING_FILE", os.path.expanduser("~/.cdtk/pairing/pairing.plist")))
        r = subprocess.run([sys.executable, os.path.join(here, "install_ipa.py"), out],
                           env=env, capture_output=True, text=True)
        print(r.stdout[-400:] if r.returncode == 0 else f"❌ 安装失败:\n{(r.stdout+r.stderr)[-500:]}")

    shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
