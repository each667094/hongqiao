#!/bin/zsh
set -eu
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
mkdir -p work/clang-cache work/swift-cache work/spm-cache work/spm-config work/spm-security outputs
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/work/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/work/swift-cache"
swift build -c release --disable-sandbox --scratch-path work/build --cache-path work/spm-cache --config-path work/spm-config --security-path work/spm-security
APP="$TASK_ROOT/outputs/鸿桥.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp work/build/release/Hongqiao "$APP/Contents/MacOS/Hongqiao"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
p={
'CFBundleExecutable':'Hongqiao','CFBundleIdentifier':'local.hongqiao.bridge',
'CFBundleName':'鸿桥','CFBundleDisplayName':'鸿桥','CFBundlePackageType':'APPL',
'CFBundleShortVersionString':'0.1.0','CFBundleVersion':'1',
'LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication',
'NSHighResolutionCapable':True,'LSApplicationCategoryType':'public.app-category.utilities',
'CFBundleIconFile':'AppIcon',
'NSLocalNetworkUsageDescription':'仅在你主动连接授权设备时使用本地网络；本地演示仅在本机运行。'
}
with open(sys.argv[1],'wb') as f: plistlib.dump(p,f)
PY
"$TASK_ROOT/work/build/release/Hongqiao" --render-preview "$TASK_ROOT/outputs/界面预览"
ICONSET="$TASK_ROOT/work/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" outputs/界面预览/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" outputs/界面预览/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
python3 - "$ICONSET" "$APP/Contents/Resources/AppIcon.icns" <<'PYICON'
import pathlib,struct,sys
folder=pathlib.Path(sys.argv[1]); chunks=[]
for kind,name in [('icp4','icon_16x16.png'),('icp5','icon_32x32.png'),('icp6','icon_32x32@2x.png'),('ic07','icon_128x128.png'),('ic08','icon_256x256.png'),('ic09','icon_512x512.png'),('ic10','icon_512x512@2x.png')]:
    data=(folder/name).read_bytes();chunks.append(kind.encode()+struct.pack('>I',len(data)+8)+data)
body=b''.join(chunks)
pathlib.Path(sys.argv[2]).write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
PYICON
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
print "已构建：$APP"
