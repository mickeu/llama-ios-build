#!/usr/bin/env python3
"""Chunked AFC upload then InstallationProxy install for large signed IPAs."""
import asyncio, os, sys, time, uuid
sys.path.insert(0, '/var/minis/skills/ios-dev/scripts')
from session import CoreDeviceSession
from pymobiledevice3.services.afc import AfcService
from pymobiledevice3.services.installation_proxy import InstallationProxyService

STAGING_DIR = "/PublicStaging/0point-install"
CHUNK = 2 * 1024 * 1024

async def main(ipa):
    size = os.path.getsize(ipa)
    remote_path = f"{STAGING_DIR}/{uuid.uuid4()}.ipa"
    last = -1
    async with CoreDeviceSession() as sess:
        print("📱 Tunnel established, chunked upload", flush=True)
        async with AfcService(sess.rsd) as afc:
            await afc.makedirs(STAGING_DIR)
            handle = await afc.fopen(remote_path, "w")
            try:
                sent, t0 = 0, time.time()
                with open(ipa, "rb") as source:
                    while block := source.read(CHUNK):
                        await asyncio.wait_for(afc.fwrite(handle, block), 90.0)
                        sent += len(block)
                        percent = int(sent * 100 / size)
                        if percent // 5 != last // 5 or sent == size:
                            print(f"  upload {percent}% ({sent // 1048576}/{size // 1048576} MiB)", flush=True)
                            last = percent
                print(f"📤 Upload OK ({time.time()-t0:.1f}s)", flush=True)
            finally:
                await afc.fclose(handle)
        inst = InstallationProxyService(sess.rsd)
        await inst.service.send_plist({"Command":"Install","ClientOptions":{"PackageType":"Developer"},"PackagePath":remote_path})
        last = -1
        while True:
            resp = await asyncio.wait_for(inst.service.recv_plist(), timeout=300.0)
            if not resp: raise RuntimeError("设备端安装服务关闭连接")
            if resp.get("Error"): raise RuntimeError(f"设备端安装错误: {resp.get('Error')}: {resp.get('ErrorDescription')}")
            pct = resp.get("PercentComplete")
            if pct is not None and (int(pct)//5 != last//5 or int(pct)>=100):
                print(f"  install {int(pct)}%", flush=True); last=int(pct)
            if resp.get("Status") == "Complete": print("✅ 安装完成", flush=True); return

if __name__ == '__main__':
    if len(sys.argv)!=2 or not os.path.isfile(sys.argv[1]): raise SystemExit('usage: install_phase2_chunked.py <signed.ipa>')
    asyncio.run(main(sys.argv[1]))
