#!/bin/zsh
set -eu
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
mkdir -p work/clang-cache work/swift-cache work/spm-cache work/spm-config work/spm-security outputs
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/work/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/work/swift-cache"
python3 scripts/verify_vendor.py
swift build -c release --disable-sandbox --scratch-path work/build --cache-path work/spm-cache --config-path work/spm-config --security-path work/spm-security
APP="$TASK_ROOT/outputs/鸿桥.app"
python3 - "$APP" <<'PYCLEAN'
import pathlib,shutil,sys
p=pathlib.Path(sys.argv[1])
if p.exists(): shutil.rmtree(p)
PYCLEAN
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/HDC" "$APP/Contents/Helpers"
cp work/build/release/Hongqiao "$APP/Contents/MacOS/Hongqiao"
cp Vendor/HDC/hdc Vendor/HDC/libusb_shared.dylib "$APP/Contents/Helpers/"
cp Vendor/HDC/NOTICE.txt Vendor/HDC/LICENSE-APACHE-2.0.txt Vendor/HDC/LICENSE-LGPL-2.1.txt Vendor/HDC/upstream.json "$APP/Contents/Resources/HDC/"
cp Vendor/HDC/THIRD-PARTY.md "$APP/Contents/Resources/开源组件说明.md"
cp -R Vendor/HDC/SourceArchives "$APP/Contents/Resources/开源源码"
chmod +x "$APP/Contents/Helpers/hdc"
codesign --force --sign - "$APP/Contents/Helpers/libusb_shared.dylib"
codesign --force --sign - "$APP/Contents/Helpers/hdc"
python3 - "$APP" <<'PYPLIST'
import plistlib,sys,pathlib,json,hashlib
app=pathlib.Path(sys.argv[1]); helper=app/'Contents/Helpers'
p={
'CFBundleExecutable':'Hongqiao','CFBundleIdentifier':'local.hongqiao.bridge',
'CFBundleName':'鸿桥','CFBundleDisplayName':'鸿桥','CFBundlePackageType':'APPL',
'CFBundleShortVersionString':'0.2.0','CFBundleVersion':'2',
'LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication',
'NSHighResolutionCapable':True,'LSApplicationCategoryType':'public.app-category.utilities',
'CFBundleIconFile':'AppIcon',
'NSLocalNetworkUsageDescription':'用于在你主动连接时与已授权手机通信。'
}
with (app/'Contents/Info.plist').open('wb') as f: plistlib.dump(p,f)
manifest={'version':'3.2.0e','bundledSHA256':{n:hashlib.sha256((helper/n).read_bytes()).hexdigest() for n in ['hdc','libusb_shared.dylib']}}
(app/'Contents/Resources/HDC/manifest.json').write_text(json.dumps(manifest,indent=2))
PYPLIST
python3 - <<'PYPREV'
import pathlib
p=pathlib.Path('outputs/界面预览');p.mkdir(exist_ok=True)
for f in p.glob('*.png'): f.unlink()
PYPREV
"$TASK_ROOT/work/build/release/Hongqiao" --render-preview "$TASK_ROOT/outputs/界面预览" --bundle-root "$APP"
ICONSET="$TASK_ROOT/work/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" outputs/界面预览/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" outputs/界面预览/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
python3 - "$ICONSET" "$APP/Contents/Resources/AppIcon.icns" <<'PYICON'
import pathlib,struct,sys
folder=pathlib.Path(sys.argv[1]);chunks=[]
for kind,name in [('icp4','icon_16x16.png'),('icp5','icon_32x32.png'),('icp6','icon_32x32@2x.png'),('ic07','icon_128x128.png'),('ic08','icon_256x256.png'),('ic09','icon_512x512.png'),('ic10','icon_512x512@2x.png')]:
 data=(folder/name).read_bytes();chunks.append(kind.encode()+struct.pack('>I',len(data)+8)+data)
body=b''.join(chunks)
pathlib.Path(sys.argv[2]).write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
PYICON
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
python3 scripts/audit_release.py
print "已构建：$APP"
