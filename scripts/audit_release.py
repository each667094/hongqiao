#!/usr/bin/env python3
import pathlib,plistlib,subprocess,json
root=pathlib.Path(__file__).resolve().parents[1]
app=root/'outputs/鸿桥.app'
# Construct old identifiers only in this test, so the release itself contains none.
removed=[''.join(['灵','犀']), ''.join(['Ly','nsi']), 'start'+'Demo', 'Hongqiao'+'Peer', 'Peer'+'Transport']
for p in (root/'Sources').rglob('*.swift'):
 text=p.read_text()
 assert not any(w.casefold() in text.casefold() for w in removed), f'源码残留已删除内容: {p}'
 assert not any(w in text for w in ['本地'+'体验','本地'+'演示']), f'源码残留已删除功能: {p}'
for p in [root/'README.md',*list((root/'docs').glob('*.md'))]:
 assert not any(w.casefold() in p.read_text().casefold() for w in removed[:2]), f'文档残留外部产品内容: {p}'
binary=(app/'Contents/MacOS/Hongqiao').read_bytes()
for word in removed:
 assert word.encode() not in binary, f'二进制残留已删除内容: {word}'
assert b'NWListener' not in binary, '产品不应包含本地服务监听器'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString']=='0.2.1'
assert not any(w.lower() in json.dumps(info).lower() for w in ['chatgpt','codex'])
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('发布包审查通过：组件、版本与内容清理已核对')
