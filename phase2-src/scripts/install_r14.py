#!/usr/bin/env python3
"""用 install_from_local 通过 CoreDevice RSD 安装大 IPA（分块上传 + 安装）。"""
import asyncio, os, sys, time, uuid
sys.path.insert(0, '/var/minis/skills/ios-dev/scripts')
from session import CoreDeviceSession
from pymobiledevice3.services.afc import AfcService
from pymobiledevice3.services.installation_proxy import InstallationProxyService

STAGING_DIR = "/PublicStaging/0point-install"
CHUNK = 1 * 1024 * 1024  # 1MB

async def main(ipa):
    size = os.path.getsize(ipa)
    remote_path = f"{STAGING_DIR}/{uuid.uuid4()}.ipa"
    async with CoreDeviceSession() as sess:
        print("Tunnel established", flush=True)
        # 1) 分块上传（每块最长 180s，绝不让单块超时中断）
        async with AfcService(sess.rsd) as afc:
            await afc.makedirs(STAGING_DIR)
            handle = await afc.fopen(remote_path, "w")
            sent, t0 = 0, time.time()
            try:
                with open(ipa, "rb") as src:
                    while True:
                        block = src.read(CHUNK)
                        if not block:
                            break
                        await asyncio.wait_for(afc.fwrite(handle, block), 180.0)
                        sent += len(block)
                        if sent % (20 * 1024 * 1024) < CHUNK or sent == size:
                            print(f"  upload {sent//1048576}/{size//1048576} MiB ({time.time()-t0:.0f}s)", flush=True)
            finally:
                await afc.fclose(handle)
        print(f"Upload OK ({time.time()-t0:.1f}s)", flush=True)

        # 2) 安装
        inst = InstallationProxyService(sess.rsd)
        await inst.service.send_plist({
            "Command": "Install",
            "ClientOptions": {"PackageType": "Developer"},
            "PackagePath": remote_path,
        })
        last = -1
        while True:
            resp = await asyncio.wait_for(inst.service.recv_plist(), timeout=600.0)
            if not resp:
                raise RuntimeError("安装服务关闭连接")
            if resp.get("Error"):
                raise RuntimeError(f"安装错误: {resp.get('Error')}: {resp.get('ErrorDescription')}")
            pct = resp.get("PercentComplete")
            if pct is not None and (int(pct)//10 != last//10 or int(pct) >= 100):
                print(f"  install {int(pct)}%", flush=True)
                last = int(pct)
            if resp.get("Status") == "Complete":
                print("安装完成", flush=True)
                return

if __name__ == '__main__':
    if len(sys.argv) != 2 or not os.path.isfile(sys.argv[1]):
        raise SystemExit('usage: install_r14.py <signed.ipa>')
    asyncio.run(main(sys.argv[1]))
