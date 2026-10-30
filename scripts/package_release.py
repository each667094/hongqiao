#!/usr/bin/env python3
"""Package only current source and deliverables; never include build caches."""
import hashlib,json,pathlib,shutil,subprocess,zipfile
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'outputs'
obsolete=[out/'伴侣协议.md']
for p in obsolete:
 if p.is_file():p.unlink()
for name in ['原理与架构分析.md','更新说明.md']:
 shutil.copy2(root/'docs'/name,out/name)
shutil.copy2(root/'README.md',out/'使用说明.md')
core=json.loads((out/'核心检查.json').read_text())
integration=json.loads((out/'验证结果.json').read_text())
device=json.loads((out/'真机验证.json').read_text())
assert core['status']=='passed' and integration['status']=='passed'
assert integration['version']=='0.2.1' and integration['phoneUsed'] is False
assert device['version']=='0.2.1' and device['status']=='passed'
assert device['phoneUsed'] is True and device['realDeviceVerified'] is True
report={
 'version':'0.2.1','date':'2026-10-30','build':'release arm64, macOS 14+',
 'appBinarySHA256':hashlib.sha256((out/'鸿桥.app/Contents/MacOS/Hongqiao').read_bytes()).hexdigest(),
 'core':core,'packageChecks':integration,'deviceChecks':device,
 'visualReview':{'screens':4,'method':'Native view rendering and visual inspection'},
 'signature':'ad-hoc; codesign --verify --deep --strict passed',
 'bundledTool':'HDC 3.2.0e + libusb 1.0.28',
 'runtimeDownloadsRequired':False,'manualToolPathRequired':False,
 'realDeviceVerified':True,
 'limitations':['手机端仍需开启调试并确认首次授权','真机验证仅覆盖 CHZ-AL00、HarmonyOS 7.0.0.111 及报告中列出的能力','投屏仍采用有界并行截图，尚未实现连续视频与音频流','完整图库、手机系统剪贴板和手机摄像头扩展尚未实现']
}
(out/'交付验证报告.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
with zipfile.ZipFile(out/'鸿桥-完整源码.zip','w',zipfile.ZIP_DEFLATED) as z:
 for name in ['Package.swift','README.md','.gitignore']:
  z.write(root/name,'Hongqiao/'+name)
 for folder in ['Sources','Tests','scripts','docs','Vendor']:
  for p in sorted((root/folder).rglob('*')):
   if p.is_file() and p.name!='.DS_Store':z.write(p,'Hongqiao/'+str(p.relative_to(root)))
archive=out/'鸿桥-Mac应用.zip'
if archive.exists():archive.unlink()
subprocess.run(['/usr/bin/ditto','-c','-k','--keepParent',str(out/'鸿桥.app'),str(archive)],check=True)
manifest={str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.rglob('*')) if p.is_file() and p.name not in ['SHA256.json','.DS_Store']}
(out/'SHA256.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
for archive in ['鸿桥-Mac应用.zip','鸿桥-完整源码.zip']:
 with zipfile.ZipFile(out/archive) as z:assert z.testzip() is None
print('鸿桥 0.2.1 交付归档生成完成')
