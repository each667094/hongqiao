import SwiftUI
import HongqiaoCore
import HongqiaoPeer

extension Color {
    static let canvas = Color(red: 0.045, green: 0.060, blue: 0.085)
    static let sidebar = Color(red: 0.065, green: 0.080, blue: 0.110)
    static let panel = Color(red: 0.085, green: 0.105, blue: 0.145)
    static let line = Color.white.opacity(0.075)
    static let muted = Color(red: 0.56, green: 0.63, blue: 0.73)
    static let mint = Color(red: 0.35, green: 0.87, blue: 0.77)
    static let accent = Color(red: 0.37, green: 0.66, blue: 1.0)
}
struct Card<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View { content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(Color.panel, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.line)) }
}
struct Pill: View {
    var text: String
    var color: Color = .mint
    var body: some View { Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 5).background(color.opacity(0.10), in: Capsule()) }
}
struct ActionButton: View {
    var title: String
    var symbol: String
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5) }
            .buttonStyle(.bordered).tint(prominent ? .accent : .white.opacity(0.16))
    }
}
struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.line)
                Group {
                    switch model.destination {
                    case .overview: OverviewView(model: model)
                    case .mirror: MirrorView(model: model)
                    case .files: FilesView(model: model)
                    case .clipboard: ClipboardView(model: model)
                    case .gallery: GalleryView(model: model)
                    case .camera: CameraView()
                    case .settings: SettingsView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }.background(Color.canvas)
        }
        .foregroundStyle(.white).font(.system(size: 13)).preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 740)
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 27, weight: .medium)).foregroundStyle(Color.mint)
                    .frame(width: 44, height: 44).background(Color.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) { Text("鸿桥").font(.system(size: 23, weight: .semibold)); Text("HONGQIAO").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.3).foregroundStyle(Color.muted) }
            }.padding(.top, 36).padding(.bottom, 38).padding(.leading, 22)
            Text("设备工作空间").font(.system(size: 10, weight: .medium)).tracking(1.2).foregroundStyle(Color.muted).padding(.horizontal, 25).padding(.bottom, 12)
            ForEach(Destination.allCases) { item in
                Button { withAnimation(.easeInOut(duration: 0.15)) { model.destination = item } } label: {
                    HStack(spacing: 12) { Image(systemName: item.symbol).font(.system(size: 16)).frame(width: 20); Text(item.rawValue); Spacer(); if item == .camera { Text("待接入").font(.system(size: 9)).foregroundStyle(Color.muted) } }
                        .foregroundStyle(model.destination == item ? Color.mint : Color.white.opacity(0.65)).padding(.horizontal, 14).frame(height: 44)
                        .background(model.destination == item ? Color.mint.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 3)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack { Circle().fill(model.connected ? Color.mint : Color.muted).frame(width: 6, height: 6); Text(model.connected ? "会话已连接" : "等待连接").font(.system(size: 12, weight: .medium)) }
                Text(model.connected ? (model.isDemo ? "仅本机模拟 · 未使用手机" : "HDC · 用户授权设备") : "先体验，再连接。\n没有手机也能探索工作流。")
                    .font(.system(size: 11)).foregroundStyle(Color.muted).lineSpacing(4)
                if model.connected { Button("断开连接") { Task { await model.disconnect() } }.buttonStyle(.plain).foregroundStyle(Color.accent).font(.system(size: 11)).disabled(model.connecting || model.busy) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).padding(14)
            HStack { Text("LOCAL FIRST").tracking(1.8); Spacer(); Text("v0.1") }.font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.muted.opacity(0.65)).padding(.horizontal, 24).padding(.bottom, 20)
        }.background(Color.sidebar).overlay(alignment: .trailing) { Rectangle().fill(Color.line).frame(width: 1) }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) { Text(model.destination.rawValue).font(.system(size: 25, weight: .semibold)); Text(model.destination.description).font(.system(size: 12)).foregroundStyle(Color.muted) }
            Spacer()
            Pill(text: model.isDemo ? "本地演示 / 非手机" : model.connected ? "HDC 已连接" : "未连接手机", color: model.connected ? .mint : .muted)
            Button { model.destination = .settings } label: { Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 18)).foregroundStyle(Color.muted).frame(width: 34, height: 34) }.buttonStyle(.plain).help("连接与诊断")
        }.padding(.horizontal, 30).padding(.vertical, 24)
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: model.busy || model.connecting ? "arrow.triangle.2.circlepath" : "info.circle").foregroundStyle(Color.mint)
            Text(model.notice).lineLimit(1)
            Spacer()
            Text("内容留在设备之间").foregroundStyle(Color.muted.opacity(0.7))
        }.font(.system(size: 10)).foregroundStyle(Color.muted).padding(.horizontal, 26).frame(height: 34).background(Color.sidebar)
    }
}
struct OverviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    hero
                    VStack(spacing: 16) {
                        Card {
                            VStack(alignment: .leading, spacing: 15) {
                                HStack { Image(systemName: "link").foregroundStyle(Color.mint); Text("连接状态").fontWeight(.semibold); Spacer(); Circle().fill(model.connected ? Color.mint : Color.muted).frame(width: 7, height: 7) }
                                Text(model.device?.name ?? "让设备准备好").font(.system(size: 20, weight: .semibold))
                                Text(model.device?.system ?? "本轮无需手机。内置演示伴侣让你先走完操作流程。").font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                                Divider().overlay(Color.line)
                                HStack { stat("连接方式", model.isDemo ? "回环网络" : model.connected ? "HDC" : "未连接"); Spacer(); stat("画面尺寸", model.image == nil ? "—" : "\(model.device?.width ?? 0) × \(model.device?.height ?? 0)") }
                                Button { model.destination = .settings } label: { HStack { Text("管理连接"); Spacer(); Image(systemName: "arrow.up.right") }.foregroundStyle(Color.accent).font(.system(size: 12)) }.buttonStyle(.plain)
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 15) {
                                HStack { Image(systemName: "shield.lefthalf.filled").foregroundStyle(Color.mint); Text("独立实现 · 本地运行").fontWeight(.medium) }
                                Text("不调用灵犀互联的服务，也不复用它的程序、图标或手机代理。演示会话只绑定本机地址，连接令牌在结束后失效。")
                                    .font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(6)
                            }
                        }
                    }.frame(width: 300)
                }
                HStack(spacing: 14) {
                    feature(.mirror, "看见，也能操作", "点击 · 滑动 · 中文输入", "rectangle.on.rectangle", .accent)
                    feature(.files, "文件在两端流转", "拖入发送 · 原文件保存", "arrow.up.arrow.down", .mint)
                    feature(.clipboard, "让文字接着走", "手动读取 · 双向传递", "doc.on.clipboard", .orange)
                }
                HStack { Image(systemName: "checkmark.seal").foregroundStyle(Color.mint); Text("本地演示是可交互的测试设备。HDC 真机功能需连接授权手机后验证。 ").foregroundStyle(Color.muted); Spacer(); Text("不等同于完整复刻版").foregroundStyle(Color.muted.opacity(0.65)) }.font(.system(size: 10)).padding(.horizontal, 4)
            }.padding(28)
        }
    }
    private var hero: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 17) {
                Pill(text: "跨设备，从这座桥开始")
                Text("手机的世界，\n在 Mac 上继续。").font(.system(size: 32, weight: .semibold)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
                Text("投屏、操作、传文件。\n一个清晰的设备工作台。").font(.system(size: 13)).foregroundStyle(Color.muted).lineSpacing(6)
                Spacer(minLength: 18)
                Button { Task { await model.startDemo() } } label: { Label(model.connected ? "重新体验演示" : "开始本地体验", systemImage: "play.fill").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(Color.canvas).background(Color.mint, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).disabled(model.connecting || model.busy)
                Button("连接我的手机 →") { model.destination = .settings }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.muted)
            }.padding(.vertical, 6)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Image(nsImage: model.image ?? DemoArtwork.image()).resizable().interpolation(.high).scaledToFit().frame(width: 170, height: 340).clipShape(RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.17), lineWidth: 5)).shadow(color: .black.opacity(0.3), radius: 20, y: 14)
                Text(model.connected ? (model.isDemo ? "本地演示设备" : "已授权设备画面") : "界面示意 · 非手机画面").font(.system(size: 9)).foregroundStyle(Color.muted)
            }
        }.padding(28).frame(maxWidth: .infinity, minHeight: 400, maxHeight: 400, alignment: .leading)
            .background(LinearGradient(colors: [Color.panel, Color(red: 0.08, green: 0.19, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.line))
    }
    private func stat(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 10)).foregroundStyle(Color.muted); Text(value).font(.system(size: 12, weight: .medium)) } }
    private func feature(_ destination: Destination, _ title: String, _ detail: String, _ symbol: String, _ color: Color) -> some View {
        Button { model.destination = destination } label: {
            VStack(alignment: .leading, spacing: 12) { HStack { Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(color); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(Color.muted).font(.system(size: 10)) }; Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white); Text(detail).font(.system(size: 10)).foregroundStyle(Color.muted) }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(Color.panel, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.line))
        }.buttonStyle(.plain)
    }
}
struct EmptyDevice: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 20) { Image(systemName: "iphone.and.arrow.forward").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(Color.muted); Text("先建立一条连接").font(.system(size: 24, weight: .medium)); Text("无需手机，可以先启动本地演示设备。").foregroundStyle(Color.muted); ActionButton(title: "开始本地体验", symbol: "play.fill", prominent: true) { Task { await model.startDemo() } }.disabled(model.connecting) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct MirrorView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if !model.connected { EmptyDevice(model: model) } else {
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 14) {
                    HStack { Pill(text: model.isDemo ? "LOCAL DEMO" : "HDC · 截图刷新"); Spacer(); Text(model.paused ? "已暂停" : "\(model.fps, specifier: "%.1f") fps").foregroundStyle(Color.muted).font(.system(size: 11, design: .monospaced)) }
                    InteractiveScreen(image: model.image, screenWidth: model.device?.width ?? 0, screenHeight: model.device?.height ?? 0, enabled: model.controlEnabled && !model.paused) { event in Task { await model.control(event) } }
                        .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.line)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(spacing: 20) {
                        tool("返回", "chevron.backward") { Task { await model.control(ControlEvent("back")) } }.disabled(!model.controlEnabled || model.paused)
                        tool("主页", "house") { Task { await model.control(ControlEvent("home")) } }.disabled(!model.controlEnabled || model.paused)
                        tool(model.paused ? "继续" : "暂停", model.paused ? "play" : "pause") { model.paused.toggle() }
                        tool("截图", "camera") { model.saveScreenshot() }.disabled(model.image == nil)
                        tool(model.recording ? "结束录屏" : "录屏", model.recording ? "stop.circle.fill" : "record.circle") { if model.recording { Task { await model.stopRecording() } } else { model.startRecording() } }.disabled(model.image == nil)
                    }.padding(.vertical, 10)
                }
                VStack(spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack { Image(systemName: "cursorarrow.rays").foregroundStyle(Color.mint); Text("反向控制").fontWeight(.semibold); Spacer(); Toggle("", isOn: $model.controlEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small) }
                            Text(model.controlEnabled ? "点击、长按、拖动或双指滚动。右键与 Esc 返回。" : "开启后才会向设备发送操作。暂停或断连时不会注入操作。")
                                .font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(5)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("中文输入", systemImage: "character.cursor.ibeam").fontWeight(.semibold)
                            TextEditor(text: $model.inputText).font(.system(size: 13)).scrollContentBackground(.hidden).padding(8).frame(height: 120).background(Color.canvas, in: RoundedRectangle(cornerRadius: 8))
                            Text("先点击设备输入框，再发送文字。不会自动点击聊天发送按钮。HDC 输入能力受系统版本约束。").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            ActionButton(title: "输入到设备", symbol: "arrow.up.right", prominent: true) { Task { await model.sendInput() } }.disabled(!model.controlEnabled || model.paused || model.inputText.isEmpty)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("画面状态").fontWeight(.semibold)
                            row("尺寸", "\(model.device?.width ?? 0) × \(model.device?.height ?? 0)")
                            row("最近取帧", "\(Int(model.latency)) ms")
                            row("累计帧数", "\(model.frames)")
                            row("录制", model.recording ? "进行中 · 无音频" : "未开始")
                            Text(model.isDemo ? "画面来自本机演示服务，不代表真实手机性能。" : "此版本用截图轮询，无法达到硬件编码视频流的流畅度。").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(4)
                        }
                    }
                }.frame(width: 280)
            }.padding(26)
        }
    }
    private func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 7) { Image(systemName: symbol).font(.system(size: 17)); Text(title).font(.system(size: 9)) }.frame(width: 50).foregroundStyle(Color.muted) }.buttonStyle(.plain) }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(Color.muted); Spacer(); Text(value).fontDesign(.monospaced) }.font(.system(size: 11)) }
}
struct FilesView: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false
    var body: some View {
        if !model.connected { EmptyDevice(model: model) } else {
            VStack(spacing: 18) {
                HStack { Image(systemName: "folder").foregroundStyle(Color.mint); if model.isDemo { Text("演示伴侣 / 文件").foregroundStyle(Color.muted) } else { TextField("设备绝对路径", text: $model.currentPath).textFieldStyle(.roundedBorder).onSubmit { Task { await model.refreshFiles() } } }; Spacer(); ActionButton(title: "刷新", symbol: "arrow.clockwise") { Task { await model.refreshFiles() } }; ActionButton(title: "发送文件", symbol: "plus", prominent: true) { Task { await model.chooseSendFiles() } }.disabled(model.busy) }
                VStack(spacing: 12) { Image(systemName: "tray.and.arrow.down").font(.system(size: 30, weight: .light)).foregroundStyle(Color.mint); Text("把文件拖到这里").font(.system(size: 16, weight: .medium)); Text(model.isDemo ? "真实字节传输到本机演示伴侣 · 单文件最大 16 MB" : "发送至当前设备目录 · 单文件最大 256 MB · 不覆盖同名文件").font(.system(size: 11)).foregroundStyle(Color.muted) }.frame(maxWidth: .infinity).frame(height: 140).background(Color.mint.opacity(dropTargeted ? 0.1 : 0.025), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.mint.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
                    .dropDestination(for: URL.self) { urls, _ in Task { await model.sendFiles(urls) }; return !urls.isEmpty && !model.busy } isTargeted: { dropTargeted = $0 }
                if !model.isDemo { Text("HDC 只能访问调试用户有权限的目录。/data/local/tmp 是调试目录，不是手机“下载”或图库；相册需要手机伴侣授权。").font(.system(size: 11)).foregroundStyle(Color.orange).frame(maxWidth: .infinity, alignment: .leading) }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.files) { file in
                            HStack(spacing: 14) {
                                Image(systemName: file.directory ? "folder.fill" : file.isImage ? "photo" : "doc.text").font(.system(size: 22)).foregroundStyle(file.isImage ? Color.mint : .accent).frame(width: 36)
                                VStack(alignment: .leading, spacing: 5) { Text(file.name).font(.system(size: 13)); Text(file.directory ? "文件夹" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.system(size: 10)).foregroundStyle(Color.muted) }
                                Spacer()
                                if file.directory { Button("打开") { model.currentPath = model.remotePath(file.name); Task { await model.refreshFiles() } }.buttonStyle(.bordered) }
                                else { Button { Task { await model.saveFile(file) } } label: { Label("保存到 Mac", systemImage: "arrow.down.to.line") }.buttonStyle(.bordered).controlSize(.small).disabled(model.busy) }
                            }.padding(15)
                            Divider().overlay(Color.line)
                        }
                        if model.files.isEmpty { Text("当前目录暂无可读取文件").foregroundStyle(Color.muted).padding(45) }
                    }.background(Color.panel, in: RoundedRectangle(cornerRadius: 13))
                }
                if let last = model.transfers.first { HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint); Text(last).lineLimit(1); Spacer() }.font(.system(size: 11)).foregroundStyle(Color.muted) }
            }.padding(28)
        }
    }
}
struct ClipboardView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if !model.connected { EmptyDevice(model: model) } else {
            VStack(alignment: .leading, spacing: 20) {
                Card {
                    HStack(spacing: 14) { Image(systemName: "hand.raised").font(.system(size: 25)).foregroundStyle(Color.mint); VStack(alignment: .leading, spacing: 6) { Text("每次读写，由你发起").font(.system(size: 16, weight: .medium)); Text("不在后台监视 Mac 剪贴板，也不自动覆盖已有内容。").foregroundStyle(Color.muted).font(.system(size: 12)) }; Spacer(); Pill(text: model.isDemo ? "演示伴侣剪贴板" : "HDC 能力受限", color: model.isDemo ? .mint : .orange) }
                }
                if !model.canReadClipboard { Text("HDC 没有公开的系统剪贴板双向接口。本页可读取 Mac 剪贴板，再到“实时投屏”输入文字；真正双向同步需手机伴侣 App。").font(.system(size: 12)).foregroundStyle(Color.orange).lineSpacing(5) }
                HStack { Text("待传递的文字").fontWeight(.medium); Spacer(); Text("不会保存到运行日志").font(.system(size: 11)).foregroundStyle(Color.muted) }
                TextEditor(text: $model.clipboardText).font(.system(size: 16)).scrollContentBackground(.hidden).padding(18).background(Color.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.line))
                HStack(spacing: 12) {
                    ActionButton(title: "读取 Mac 剪贴板", symbol: "doc.on.clipboard") { model.readMacClipboard() }
                    ActionButton(title: "复制到 Mac", symbol: "doc.on.doc") { model.copyToMac() }
                    Spacer()
                    ActionButton(title: "从设备读取", symbol: "arrow.down") { Task { await model.readClipboard() } }.disabled(!model.canReadClipboard)
                    ActionButton(title: "写入设备", symbol: "arrow.up", prominent: true) { Task { await model.writeClipboard() } }.disabled(!model.canReadClipboard)
                }
            }.padding(28)
        }
    }
}
struct GalleryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if !model.connected { EmptyDevice(model: model) } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text(model.isDemo ? "演示相册" : "当前可访问目录中的图片").font(.system(size: 20, weight: .semibold)); Pill(text: "\(model.photoFiles.count) 张", color: .muted); Spacer(); ActionButton(title: "刷新", symbol: "arrow.clockwise") { Task { await model.refreshFiles() } } }
                Text(model.isDemo ? "以下图片由程序绘制，不是用户照片。保存会下载伴侣中的原文件。" : "仅显示调试目录中有权限读取的图片，不代表已获得手机图库权限。可在“文件互传”切换目录。")
                    .font(.system(size: 12)).foregroundStyle(Color.muted)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 18) {
                        ForEach(model.photoFiles) { file in
                            VStack(alignment: .leading, spacing: 12) {
                                if let image = model.photos[file.name] { Image(nsImage: image).resizable().scaledToFill().frame(height: 158).clipped().clipShape(RoundedRectangle(cornerRadius: 10)) }
                                else { RoundedRectangle(cornerRadius: 10).fill(Color.canvas).frame(height: 158).overlay(Image(systemName: "photo").foregroundStyle(Color.muted)) }
                                HStack { Text(file.name).lineLimit(1).font(.system(size: 12)); Spacer(); Button { Task { await model.saveFile(file) } } label: { Image(systemName: "arrow.down.to.line").foregroundStyle(Color.mint) }.buttonStyle(.plain).disabled(model.busy) }
                            }.padding(12).background(Color.panel, in: RoundedRectangle(cornerRadius: 15))
                        }
                    }
                    if model.photoFiles.isEmpty { Text("当前目录暂无可读取图片").foregroundStyle(Color.muted).padding(70) }
                }
            }.padding(28)
        }
    }
}
struct CameraView: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "video.badge.ellipsis").font(.system(size: 60, weight: .ultraLight)).foregroundStyle(Color.muted)
            Text("手机摄像头 · 尚未接入").font(.system(size: 24, weight: .medium))
            Text("要在 FaceTime 或会议软件中出现，需要手机采集视频，\n以及拥有独立签名、权限和用户批准的 CoreMediaIO 扩展。\n\n本地版本未安装系统扩展，也未打开 Mac 摄像头。")
                .multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(Color.muted).lineSpacing(8)
            Pill(text: "此功能未实现，不计入已完成功能", color: .orange)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 18) {
                    Card { VStack(alignment: .leading, spacing: 14) { HStack { Image(systemName: "desktopcomputer").foregroundStyle(Color.mint); Text("本地演示").fontWeight(.semibold); Spacer(); Pill(text: "无需手机") }; Text("内置伴侣经本机 HTTP 接口传输图像、操作、文字与文件。不会发现或连接真实手机。").font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(5); ActionButton(title: "启动演示设备", symbol: "play.fill", prominent: true) { Task { await model.startDemo() } }.disabled(model.connecting || model.busy) } }
                    Card { VStack(alignment: .leading, spacing: 14) { HStack { Image(systemName: "cable.connector").foregroundStyle(Color.accent); Text("真实设备 · HDC").fontWeight(.semibold); Spacer(); Pill(text: "待真机验证", color: .orange) }; Text("使用官方 SDK 的调试工具，经 USB 或用户指定的无线调试端口连接。只在点击按钮后操作。").font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(5); Text("本轮未使用手机").font(.system(size: 12)).foregroundStyle(Color.orange).padding(.vertical, 8) } }
                }
                Card {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("HDC 连接设置").font(.system(size: 16, weight: .semibold))
                        HStack { TextField("选择 DevEco SDK / toolchains / hdc", text: $model.hdcPath).textFieldStyle(.roundedBorder); Button("选择工具…") { model.chooseHDC() }; Button("发现设备") { Task { await model.discoverDevices() } }.disabled(model.hdcPath.isEmpty || model.busy) }
                        Text("不使用灵犀应用包中的 HDC。工具请从自己的华为开发环境中选择；应用不会自动扫描、安装或启动第三方工具。").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(4)
                        HStack { Text("已授权设备").foregroundStyle(Color.muted).frame(width: 80, alignment: .leading); Picker("", selection: $model.selectedTarget) { Text("请选择").tag(""); ForEach(model.devices, id: \.self) { Text($0).tag($0) } }.labelsHidden(); Button("连接设备") { Task { await model.connectHDC() } }.disabled(model.selectedTarget.isEmpty || model.busy || model.connecting) }
                        Divider().overlay(Color.line)
                        HStack { Text("无线调试").foregroundStyle(Color.muted).frame(width: 80, alignment: .leading); TextField("手机 IPv4:当前调试端口", text: $model.wirelessEndpoint).textFieldStyle(.roundedBorder); Button("连接此地址") { Task { await model.wirelessConnect() } }.disabled(model.hdcPath.isEmpty || model.wirelessEndpoint.isEmpty || model.busy) }
                        Text("端口必须从手机“无线调试”页读取，不是固定端口或配对码。首次连接需在手机上确认信任。应用不修改手机系统设置。").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(4)
                    }
                }
                Card {
                    HStack { VStack(alignment: .leading, spacing: 8) { Text("取帧间隔").fontWeight(.medium); Text("截图轮询模式；更快的设置不会突破设备实际处理速度。").font(.system(size: 11)).foregroundStyle(Color.muted) }; Spacer(); Picker("", selection: $model.frameInterval) { Text("0.25 秒").tag(0.25); Text("0.5 秒").tag(0.5); Text("1 秒").tag(1.0); Text("2 秒").tag(2.0) }.frame(width: 110).labelsHidden() }
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("本轮运行记录").font(.system(size: 16, weight: .semibold)); Spacer(); Button("导出诊断…") { model.exportDiagnostics() } }
                        Text("不记录输入文字、剪贴板内容、配对令牌或截图。未连接手机时的成功仅说明本地流程通过。").font(.system(size: 11)).foregroundStyle(Color.muted)
                        ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(Array(model.logs.prefix(30).enumerated()), id: \.offset) { _, value in Text(value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }; if model.logs.isEmpty { Text("暂无运行记录").foregroundStyle(Color.muted) } }.padding(12) }.frame(height: 170).background(Color.canvas, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }.padding(28)
        }
    }
}
