# 鸿桥 Hongqiao

独立开发的原生 Mac 跨设备工作台。当前提供可交互的本地演示、真实 HDC 后端、截图 / MOV 录屏、双向文件传输、剪贴板与图片浏览 UI。**不是已完成全部功能的灵犀互联替代品。** 本轮没有使用手机。

## 直接运行

打开 `outputs/鸿桥.app`，点击“开始本地体验”。无需手机、无需登录、不需要 Python / Node。演示所有手机内容均在本机模拟，文件传输和网络请求实际执行。

系统要求：Apple Silicon Mac，macOS 14 或以上。该构建使用本地 ad-hoc 签名，未公证，不适合直接作为公开分发版本。

## 使用真实手机（本轮未验证）

在“连接与诊断”选择你自己安装的官方 HarmonyOS SDK 的 `hdc`，再主动点击发现设备。USB 调试授权或手机当前无线调试 IPv4:端口由用户配置。应用不会自动搜索手机，也不使用已安装灵犀应用中的二进制文件。

HDC 投屏是截图轮询；文件默认访问 `/data/local/tmp` 调试目录。没有手机伴侣时，不能宣称获得完整图库或双向系统剪贴板；相关页面会说明能力边界。

## 构建与验证

```sh
./scripts/build.sh
./scripts/verify.sh
```

使用本机 Swift 6 / Command Line Tools；无第三方 Swift 包。构建缓存都放项目 `work/`。

可执行文件支持：

```sh
outputs/鸿桥.app/Contents/MacOS/Hongqiao --verify
outputs/鸿桥.app/Contents/MacOS/Hongqiao --render-preview outputs/界面预览
```

`--verify` 只启动本地演示，不触碰手机，不读写 Mac 系统剪贴板，不启动摄像头。正常 UI 中仅在点击按钮后读取或覆盖 Mac 剪贴板。

## 文档

- `docs/原理与架构分析.md`：安装包证据、架构推断、独立实现与功能差距。
- `docs/伴侣协议.md`：本地演示 API 与未来手机侧接入边界。
- `docs/installed-app-observations.json`：精简的安装包元数据观察。
- `outputs/验证结果.json`：端到端验证状态，`realDeviceVerified` 明确为 false。

目前未实现：原生手机伴侣、连续低延迟视频流 / 音频、蓝牙 HID、系统摄像头扩展、完整用户图库权限、后台自动重连、公开分发签名与公证。
