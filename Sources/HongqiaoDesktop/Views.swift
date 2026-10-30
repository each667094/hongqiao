import SwiftUI
import HongqiaoCore

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
        .sheet(isPresented: $model.showConnectionGuide) { ConnectionGuideView() }
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
                Text(model.connected ? "手机已授权连接" : "连接手机，开始投屏。\n首次使用需在手机上授权。")
                    .font(.system(size: 11)).foregroundStyle(Color.muted).lineSpacing(4)
                if model.connected { Button("断开连接") { Task { await model.disconnect() } }.buttonStyle(.plain).foregroundStyle(Color.accent).font(.system(size: 11)).disabled(model.connecting || model.busy) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).padding(14)
            HStack { Text("LOCAL FIRST").tracking(1.8); Spacer(); Text("v0.2.1") }.font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.muted.opacity(0.65)).padding(.horizontal, 24).padding(.bottom, 20)
        }.background(Color.sidebar).overlay(alignment: .trailing) { Rectangle().fill(Color.line).frame(width: 1) }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) { Text(model.destination.rawValue).font(.system(size: 25, weight: .semibold)); Text(model.destination.description).font(.system(size: 12)).foregroundStyle(Color.muted) }
            Spacer()
            Pill(text: model.connected ? "手机已连接" : "未连接手机", color: model.connected ? .mint : .muted)
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
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        Pill(text: "跨设备，从这座桥开始")
                        Text("手机的世界，\n在 Mac 上继续。").font(.system(size: 34, weight: .semibold)).lineSpacing(8)
                        Text("连接手机，即可投屏、操作和传文件。\n连接工具已随鸿桥安装，无需另装开发环境。")
                            .font(.system(size: 13)).foregroundStyle(Color.muted).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 16) {
                            Button { if model.connected { model.destination = .mirror } else { Task { await model.connectPhone() } } } label: {
                                Label(model.connecting ? "正在连接…" : model.connected ? "打开手机投屏" : "连接手机", systemImage: model.connected ? "rectangle.on.rectangle" : "cable.connector")
                                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 12).foregroundStyle(Color.canvas).background(Color.mint, in: RoundedRectangle(cornerRadius: 11))
                            }.buttonStyle(.plain).disabled(model.connecting || model.busy || !model.componentReady)
                            Button("查看连接步骤") { model.showConnectionGuide = true }.buttonStyle(.plain).foregroundStyle(Color.accent)
                        }.padding(.top, 10)
                        if model.connectionTitle != "准备连接手机" { Text(model.connectionTitle).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.mint) }
                    }
                    Spacer(minLength: 20)
                    VStack(spacing: 20) {
                        if let image = model.image {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 160, height: 300).clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            ZStack {
                                Circle().fill(Color.mint.opacity(0.035)).frame(width: 220, height: 220)
                                Circle().stroke(Color.mint.opacity(0.12), lineWidth: 1).frame(width: 180, height: 180)
                                Image(systemName: "iphone.gen3").font(.system(size: 112, weight: .ultraLight)).foregroundStyle(Color.mint.opacity(0.8))
                                Image(systemName: "cable.connector").font(.system(size: 24)).foregroundStyle(Color.mint).offset(y: 88)
                            }.frame(width: 240, height: 300)
                        }
                        Text(model.device?.name ?? "等待你的手机").font(.system(size: 11)).foregroundStyle(Color.muted)
                    }
                }.padding(32).frame(maxWidth: .infinity, minHeight: 390, alignment: .leading)
                    .background(LinearGradient(colors: [Color.panel, Color(red: 0.07, green: 0.17, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.line))
                HStack(spacing: 16) {
                    quickStep("1", "连接数据线", "用支持数据传输的线连接手机。")
                    quickStep("2", "在手机上授权", "开启 USB 调试，确认允许连接。")
                    quickStep("3", "点击连接手机", "单台手机会自动连接并打开投屏。")
                }
                if !model.devices.isEmpty || model.connectionTitle == "还没有发现手机" || model.connectionTitle == "请在手机上允许连接" {
                    ConnectionPanel(model: model)
                }
                HStack { Image(systemName: "lock.shield").foregroundStyle(Color.mint); Text("每次连接由你发起，反向控制需手动开启。").foregroundStyle(Color.muted); Spacer(); Button("使用无线连接 →") { model.connectionMethod = .wireless; model.resetConnectionChoices(); model.destination = .settings }.buttonStyle(.plain).foregroundStyle(Color.accent).disabled(model.connected || model.connecting) }.font(.system(size: 11)).padding(.horizontal, 5)
            }.padding(28)
        }
    }
    private func quickStep(_ number: String, _ title: String, _ detail: String) -> some View {
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 12) {
                Text(number).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Color.mint).frame(width: 28, height: 28).background(Color.mint.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 13, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        }
    }
}
struct EmptyDevice: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(Color.muted)
            Text("连接手机，开始使用").font(.system(size: 24, weight: .medium))
            Text("用数据线连接手机，并在手机上确认调试授权。\n连接工具已内置，无需下载或配置路径。")
                .multilineTextAlignment(.center).foregroundStyle(Color.muted).lineSpacing(7)
            ActionButton(title: model.connecting ? "正在连接…" : "连接手机", symbol: "cable.connector", prominent: true) { Task { await model.connectPhone() } }.disabled(model.connecting || !model.componentReady)
            Button("查看连接步骤") { model.showConnectionGuide = true }.buttonStyle(.plain).foregroundStyle(Color.accent)
            if model.connectionTitle != "准备连接手机" { Text(model.connectionTitle).foregroundStyle(Color.mint); Button("前往连接页面") { model.destination = .settings }.buttonStyle(.plain).foregroundStyle(Color.accent) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct MirrorView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if !model.connected { EmptyDevice(model: model) } else {
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 14) {
                    HStack { Pill(text: "手机画面"); Spacer(); Text(model.paused ? "已暂停" : "\(model.fps, specifier: "%.1f") fps").foregroundStyle(Color.muted).font(.system(size: 11, design: .monospaced)) }
                    InteractiveScreen(image: model.image, screenWidth: model.device?.width ?? 0, screenHeight: model.device?.height ?? 0, enabled: model.controlEnabled && !model.paused) { event in Task { await model.control(event) } }
                        .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.line)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(spacing: 20) {
                        tool("返回", "chevron.backward") { Task { await model.control(ControlEvent("back")) } }.disabled(!model.controlEnabled || model.paused)
                        tool("主页", "house") { Task { await model.control(ControlEvent("home")) } }.disabled(!model.controlEnabled || model.paused)
                        tool(model.paused ? "继续" : "暂停", model.paused ? "play" : "pause") { Task { await model.setPaused(!model.paused) } }
                        tool("截图", "camera") { model.saveScreenshot() }.disabled(model.image == nil)
                        tool(model.recording ? "结束录屏" : "录屏", model.recording ? "stop.circle.fill" : "record.circle") { if model.recording { Task { await model.stopRecording() } } else { model.startRecording() } }.disabled(model.image == nil)
                    }.padding(.vertical, 10)
                }
                VStack(spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack { Image(systemName: "cursorarrow.rays").foregroundStyle(Color.mint); Text("反向控制").fontWeight(.semibold); Spacer(); Toggle("", isOn: $model.controlEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small) }
                            Text(model.controlEnabled ? model.controlStatus : "开启后才会向设备发送操作。暂停或断连时不会注入操作。")
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
                            Text("自动模式优先降低延迟；显示实测帧率。录屏不包含声音。").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(4)
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
                HStack { Image(systemName: "folder").foregroundStyle(Color.mint); TextField("设备目录", text: $model.currentPath).textFieldStyle(.roundedBorder).onSubmit { Task { await model.refreshFiles() } }; Spacer(); ActionButton(title: "刷新", symbol: "arrow.clockwise") { Task { await model.refreshFiles() } }; ActionButton(title: "发送文件", symbol: "plus", prominent: true) { Task { await model.chooseSendFiles() } }.disabled(model.busy) }
                VStack(spacing: 12) { Image(systemName: "tray.and.arrow.down").font(.system(size: 30, weight: .light)).foregroundStyle(Color.mint); Text("把文件拖到这里").font(.system(size: 16, weight: .medium)); Text("发送至当前设备目录 · 单文件最大 256 MB · 不覆盖同名文件").font(.system(size: 11)).foregroundStyle(Color.muted) }.frame(maxWidth: .infinity).frame(height: 140).background(Color.mint.opacity(dropTargeted ? 0.1 : 0.025), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.mint.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
                    .dropDestination(for: URL.self) { urls, _ in Task { await model.sendFiles(urls) }; return !urls.isEmpty && !model.busy } isTargeted: { dropTargeted = $0 }
                Text("此页显示手机允许访问的调试目录，不是手机的“下载”或完整图库。").font(.system(size: 11)).foregroundStyle(Color.muted).frame(maxWidth: .infinity, alignment: .leading)
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
                    HStack(spacing: 14) { Image(systemName: "hand.raised").font(.system(size: 25)).foregroundStyle(Color.mint); VStack(alignment: .leading, spacing: 6) { Text("每次读写，由你发起").font(.system(size: 16, weight: .medium)); Text("不在后台监视 Mac 剪贴板，也不自动覆盖已有内容。").foregroundStyle(Color.muted).font(.system(size: 12)) }; Spacer(); Pill(text: "文字接力", color: .mint) }
                }
                if !model.canReadClipboard { Text("先在“实时投屏”中开启反向控制，点击手机输入框，再将这里的文字输入手机。暂不支持读取或改写手机的系统剪贴板。").font(.system(size: 12)).foregroundStyle(Color.orange).lineSpacing(5) }
                HStack { Text("待传递的文字").fontWeight(.medium); Spacer(); Text("不会保存到运行日志").font(.system(size: 11)).foregroundStyle(Color.muted) }
                TextEditor(text: $model.clipboardText).font(.system(size: 16)).scrollContentBackground(.hidden).padding(18).background(Color.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.line))
                HStack(spacing: 12) {
                    ActionButton(title: "读取 Mac 剪贴板", symbol: "doc.on.clipboard") { model.readMacClipboard() }
                    ActionButton(title: "复制到 Mac", symbol: "doc.on.doc") { model.copyToMac() }
                    Spacer()
                    ActionButton(title: "输入到手机", symbol: "arrow.up.right", prominent: true) {
                        model.inputText = model.clipboardText
                        Task { await model.sendInput() }
                    }.disabled(!model.controlEnabled || model.paused || model.clipboardText.isEmpty)
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
                HStack { Text("当前目录的图片").font(.system(size: 20, weight: .semibold)); Pill(text: "\(model.photoFiles.count) 张", color: .muted); Spacer(); ActionButton(title: "刷新", symbol: "arrow.clockwise") { Task { await model.refreshFiles() } } }
                Text("仅显示当前目录中允许读取的图片。可在“文件互传”中切换目录，暂不支持完整手机图库。")
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
struct ConnectionPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("连接手机").font(.system(size: 19, weight: .semibold)); Spacer(); Pill(text: model.componentReady ? "连接组件已内置" : "连接组件不完整", color: model.componentReady ? .mint : .orange) }
                Text(model.componentStatus).font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                Picker("连接方式", selection: $model.connectionMethod) { ForEach(ConnectionMethod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 360).disabled(model.connecting || model.connected).onChange(of: model.connectionMethod) { _, _ in model.resetConnectionChoices() }
                if model.connectionMethod == .usb {
                    VStack(alignment: .leading, spacing: 10) {
                        step("1", "用数据线连接手机与 Mac。")
                        step("2", "在手机设置中开启 USB 调试，并保持解锁。")
                        step("3", "在手机弹出的授权窗口中点击允许。")
                    }
                } else {
                    Text("让手机与 Mac 连接同一 Wi-Fi，在手机“开发者选项 → 无线调试”中查看连接信息。").font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) { Text("手机 IP 地址").font(.system(size: 11)).foregroundStyle(Color.muted); TextField("例如 192.168.1.8", text: $model.wirelessHost).textFieldStyle(.roundedBorder) }
                        VStack(alignment: .leading, spacing: 7) { Text("手机显示的端口").font(.system(size: 11)).foregroundStyle(Color.muted); TextField("填写当前端口", text: $model.wirelessPort).textFieldStyle(.roundedBorder) }.frame(width: 170)
                    }.disabled(model.connecting || model.connected)
                    Text("端口以手机当前显示为准，无需填写配对码。").font(.system(size: 11)).foregroundStyle(Color.muted)
                }
                Divider().overlay(Color.line)
                HStack(alignment: .top, spacing: 12) {
                    if model.connecting { ProgressView().controlSize(.small).padding(.top, 3) } else { Image(systemName: model.connected ? "checkmark.circle.fill" : "iphone").foregroundStyle(Color.mint).padding(.top, 3) }
                    VStack(alignment: .leading, spacing: 6) { Text(model.connected ? (model.device?.name ?? "手机已连接") : model.connectionTitle).font(.system(size: 14, weight: .medium)); Text(model.connectionDetail).font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true) }
                }
                if !model.devices.isEmpty {
                    HStack { Picker("选择手机", selection: $model.selectedTarget) { ForEach(model.devices, id: \.self) { Text($0).tag($0) } }; ActionButton(title: "连接选中手机", symbol: "link", prominent: true) { Task { await model.connectSelectedPhone() } }.disabled(model.connecting || model.busy) }
                }
                HStack(spacing: 15) {
                    ActionButton(title: model.connecting ? "正在连接…" : model.connected ? "打开手机投屏" : "连接手机", symbol: model.connected ? "rectangle.on.rectangle" : "link", prominent: true) {
                        if model.connected { model.destination = .mirror } else { Task { await model.connectPhone() } }
                    }.disabled(model.connecting || model.busy || !model.componentReady)
                    Button("查看手机设置步骤") { model.showConnectionGuide = true }.buttonStyle(.plain).foregroundStyle(Color.accent)
                    Spacer()
                    if model.connected { Button("断开连接") { Task { await model.disconnect() } }.disabled(model.connecting || model.busy) }
                }
            }
        }
    }
    private func step(_ number: String, _ text: String) -> some View {
        HStack(spacing: 11) { Text(number).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.mint).frame(width: 22, height: 22).background(Color.mint.opacity(0.1), in: Circle()); Text(text).font(.system(size: 12)).foregroundStyle(Color.muted) }
    }
}
struct ConnectionGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("首次连接手机").font(.system(size: 25, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
            Text("Mac 上无需额外安装工具。请在手机完成以下设置后，回到鸿桥点击“连接手机”。").font(.system(size: 13)).foregroundStyle(Color.muted).lineSpacing(5)
            guide("1", "开启开发者选项", "在手机设置中搜索“关于”，进入关于本机，连续快速点击“软件版本号”7 次，按提示确认并重启。已开启的手机可跳过此步。")
            guide("2", "开启 USB 调试", "在手机设置中搜索“开发者选项”，进入后开启 USB 调试。使用支持数据传输的线连接 Mac，保持手机解锁。")
            guide("3", "允许这台 Mac 连接", "在手机弹出的调试授权窗口中确认允许，然后点击鸿桥的“连接手机”。只有一台已授权手机时会自动打开投屏。")
            Text("使用无线连接时，在手机开启“无线调试”，将页面上的 IP 地址与端口填入鸿桥。首次连接仍需在手机上确认授权。").font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(5)
            Link("查看华为官方开发者选项说明", destination: URL(string: "https://consumer.huawei.com/cn/support/content/zh-cn02842747/")!).font(.system(size: 12)).foregroundStyle(Color.accent)
        }.padding(32).frame(width: 620).foregroundStyle(.white).background(Color.canvas).preferredColorScheme(.dark)
    }
    private func guide(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Text(number).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.mint).frame(width: 30, height: 30).background(Color.mint.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 15, weight: .medium)); Text(detail).font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ConnectionPanel(model: model)
                Card {
                    HStack { VStack(alignment: .leading, spacing: 8) { Text("画面刷新").fontWeight(.medium); Text("自动模式使用有界采集流水线，实际帧率取决于手机与连接状态。").font(.system(size: 11)).foregroundStyle(Color.muted) }; Spacer(); Picker("", selection: $model.frameInterval) { Text("自动 · 优先流畅").tag(0.0); Text("0.25 秒").tag(0.25); Text("0.5 秒").tag(0.5); Text("1 秒").tag(1.0); Text("2 秒").tag(2.0) }.frame(width: 110).labelsHidden() }
                }
                DisclosureGroup("关于鸿桥与开源组件") {
                    HStack {
                        Text("鸿桥 0.2.1 · Apple Silicon").font(.system(size: 12)).foregroundStyle(Color.muted)
                        Spacer()
                        Button("查看开源组件说明") {
                            if let url = Bundle.main.url(forResource: "开源组件说明", withExtension: "md") { NSWorkspace.shared.open(url) }
                        }
                    }.padding(.top, 12)
                }.font(.system(size: 12)).foregroundStyle(Color.muted)
                DisclosureGroup("连接诊断") {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Text("运行记录").font(.system(size: 16, weight: .semibold)); Spacer(); Button("导出诊断…") { model.exportDiagnostics() } }
                            Text("不主动保存输入文字、剪贴板内容或画面。诊断文件不会自动上传。").font(.system(size: 11)).foregroundStyle(Color.muted)
                            ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(Array(model.logs.prefix(30).enumerated()), id: \.offset) { _, value in Text(value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }; if model.logs.isEmpty { Text("暂无运行记录").foregroundStyle(Color.muted) } }.padding(12) }.frame(height: 150).background(Color.canvas, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }.padding(.top, 10)
                }.font(.system(size: 12)).foregroundStyle(Color.muted)
            }.padding(28)
        }
    }
}
