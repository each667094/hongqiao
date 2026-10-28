#!/usr/bin/env python3
"""Fail before packaging if the pinned upstream binaries or notices changed."""
import pathlib,hashlib,json
root=pathlib.Path(__file__).resolve().parents[1]/'Vendor/HDC'
manifest=json.loads((root/'upstream.json').read_text())
for name,expected in manifest['filesSHA256'].items():
 p=root/name
 assert p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==expected, f'上游组件校验失败: {name}'
archive=root/'SourceArchives/libusb-openharmony-b982552.tar.gz'
assert archive.is_file() and hashlib.sha256(archive.read_bytes()).hexdigest()==manifest['sourceArchiveSHA256'], 'USB 对应源码校验失败'
print('上游连接组件校验通过')
