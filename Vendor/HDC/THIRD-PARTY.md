# 鸿桥开源连接组件说明

鸿桥 0.2.0 内置以下组件，用户无需单独下载安装。

| 组件 | 版本 | 来源与许可 |
| --- | --- | --- |
| OpenHarmony HDC | 3.2.0e，macOS arm64 | OpenHarmony SDK 26.0.0.25，Apache-2.0；详见完整 NOTICE |
| libusb 动态库 | 1.0.28 | OpenHarmony SDK 配套动态库，LGPL-2.1；附对应发行标签源码与补丁 |

二进制取得自 OpenHarmony 官方发行镜像：
https://repo.huaweicloud.com/openharmony/os/7.0-Beta1/L2-SDK-MAC-M1-PUBLIC.tar.gz

发布包校验值由同一官方镜像的 `.sha256` 文件核对；完整值、组件 ZIP 校验值及原始文件校验值保存在 `upstream.json`。SDK 发行版名称为 OpenHarmony 7.0 Beta1；手机系统兼容性需另做真机验证。

HDC 源码：https://gitcode.com/openharmony/developtools_hdc

USB 库对应源码：https://gitcode.com/openharmony/third_party_libusb

源码标签 `OpenHarmony-v7.0-Beta1`，提交 `b982552012b9faf15db3bd5c714594da91df33b0`。应用的“开源源码”目录附 `libusb-openharmony-b982552.tar.gz`，包括原始 libusb-1.0.28 源码包、OpenHarmony 补丁、BUILD.gn、平台配置与 COPYING。构建细节见该源码仓库的 README、install.sh 和 BUILD.gn；可按 OpenHarmony 对应 SDK 构建流程重建。

USB 库使用动态链接。可以检查、修改并替换它；鸿桥不为这些修改增加许可限制，也不禁止为调试库修改而进行的逆向工程。替换文件后，按本地构建脚本重新签名并更新组件校验清单即可。应用不启用阻止替换库的 Hardened Runtime Library Validation。运行时校验用于检测损坏，不限制对软件的自主修改。

鸿桥未修改以上组件的功能代码。本地打包会为运行环境重新进行 ad-hoc 签名，因此包内二进制哈希可能与原始发行文件不同。两类哈希分别保存在 `manifest.json` 和 `upstream.json`，不混作上游原始校验值。

完整版权、许可证和组件归属请阅读 `Vendor/HDC`（应用包内为 `Contents/Resources/HDC`）中的 `NOTICE.txt`、`LICENSE-APACHE-2.0.txt` 与 `LICENSE-LGPL-2.1.txt`。HDC 所链接的 libuv、OpenSSL、lz4、cJSON、bounds_checking 等组件归属也保留在完整 NOTICE 中。不得因为品牌清理而删除开源组件的法定归属信息。
