import AppKit
import SwiftUI
import TraceflowCore

@MainActor
final class MenuEditingCoordinator: ObservableObject {
    @Published var editing: SessionTitleEditingState?
    @Published var retainedSession: SessionSnapshot?
    @Published var focusGeneration = 0
    private var pendingAction: (() -> Void)?
    private var saving = false
    private var blurTask: Task<Void, Never>?
    let model: AppModel
    init(model: AppModel) { self.model = model }

    func begin(_ session: SessionSnapshot) {
        performAfterSaving { [weak self] in
            guard let self else { return }
            self.retainedSession = session
            self.editing = SessionTitleEditingState(model: self.model, session: session)
        }
    }

    func cancel() {
        blurTask?.cancel()
        guard !saving else { return }
        editing = nil
        retainedSession = nil
        pendingAction = nil
    }

    func scheduleBlurSave() {
        guard !saving else { return }
        blurTask?.cancel()
        blurTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            performAfterSaving {}
        }
    }

    func performAfterSaving(_ action: @escaping () -> Void) {
        blurTask?.cancel()
        guard let editing else { action(); return }
        guard !saving else { pendingAction = action; return }
        if editing.draft == (editing.session?.effectiveConversationTitle ?? "") {
            cancel(); action(); return
        }
        pendingAction = action
        saving = true
        Task {
            let success = await editing.save()
            saving = false
            guard success else { pendingAction = nil; focusGeneration += 1; return }
            let next = pendingAction
            cancel()
            next?()
        }
    }

    func restore() {
        blurTask?.cancel()
        guard let editing, !saving else { return }
        saving = true
        Task {
            let success = await editing.restore()
            saving = false
            if success { cancel() } else { focusGeneration += 1 }
        }
    }
}

struct MenuWindowView: View {
    @ObservedObject var model: AppModel
    unowned let controller: MenuWindowController
    @StateObject private var coordinator: MenuEditingCoordinator
    @State private var colorSession: String?
    @FocusState private var focusedTitle: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, controller: MenuWindowController) {
        self.model = model
        self.controller = controller
        _coordinator = StateObject(wrappedValue: MenuEditingCoordinator(model: model))
    }

    private var sessions: [SessionSnapshot] {
        var result = model.recentSessions
        if let retained = coordinator.retainedSession, coordinator.editing != nil,
           !result.contains(where: { $0.id == retained.id }) { result.append(retained) }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "diamond.fill").frame(width: 28, height: 28).foregroundStyle(.white)
                    .background(.primary, in: RoundedRectangle(cornerRadius: 9))
                Text("Traceflow").font(.headline)
                Spacer()
                Button { coordinator.performAfterSaving { controller.closeImmediately(); model.openSettingsWindow() } } label: {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain).help("设置").accessibilityLabel("设置")
            }.padding(.horizontal, 18).padding(.vertical, 16)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    checkButton("显示 HUD", value: $model.isHUDVisible)
                    checkButton("钉住 HUD", value: $model.isHUDPinned)
                }
                HStack(spacing: 8) {
                    Picker("HUD 布局", selection: $model.hudLayoutMode) {
                        ForEach(HUDLayoutMode.allCases) { Text($0.menuTitle).tag($0) }
                    }
                    Picker("HUD 显示模式", selection: $model.hudDisplayStyle) {
                        ForEach(HUDDisplayStyle.allCases) { Text($0.menuTitle).tag($0) }
                    }
                }.pickerStyle(.menu)
                HStack {
                    Text("活跃会话").font(.headline)
                    Text("· 最近 10 分钟").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.recentSessions.count) 个会话").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
                ScrollView {
                    VStack(spacing: 0) {
                        if sessions.isEmpty {
                            if model.isDiscoveringRecentSessions { ProgressView("正在读取最近会话……").controlSize(.small).padding() }
                            else { Text("最近 10 分钟没有动态").foregroundStyle(.secondary).padding() }
                        }
                        ForEach(sessions) { session in
                            sessionRow(model.sessions.first(where: { $0.id == session.id }) ?? session)
                            if session.id != sessions.last?.id { Divider() }
                        }
                        if let message = model.recentDiscoveryMessage { Text(message).font(.caption).foregroundStyle(.secondary).padding(8) }
                        if let message = model.markerColorErrorMessage { Text(message).font(.caption).foregroundStyle(.red).padding(8) }
                    }.frame(maxWidth: .infinity)
                }.background(.background, in: RoundedRectangle(cornerRadius: 12))
            }.padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            HStack { Spacer(); Button("退出 Traceflow") { coordinator.performAfterSaving { NSApplication.shared.terminate(nil) } }.buttonStyle(.plain) }
                .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 410, height: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onAppear { controller.requestClose = { coordinator.performAfterSaving { controller.closeImmediately() } } }
        .onChange(of: coordinator.editing?.sessionID) { _, id in focusedTitle = id != nil }
        .onChange(of: coordinator.focusGeneration) { _, _ in focusedTitle = true }
        .onChange(of: focusedTitle) { _, focused in
            if !focused, coordinator.editing != nil { coordinator.scheduleBlurSave() }
        }
    }

    private func checkButton(_ title: String, value: Binding<Bool>) -> some View {
        Button { coordinator.performAfterSaving { value.wrappedValue.toggle() } } label: {
            HStack { Text(title); Spacer(); if value.wrappedValue { Image(systemName: "checkmark") } }
                .padding(10).frame(maxWidth: .infinity)
                .background(value.wrappedValue ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityValue(value.wrappedValue ? "已开启" : "已关闭")
    }

    private func sessionRow(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 10) {
            Button { coordinator.performAfterSaving { colorSession = session.id } } label: {
                SessionMarkerView(colorHex: session.persisted.markerColorHex).frame(width: 24, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!model.sessionDataHealth.allowsSaving)
                .accessibilityLabel("修改会话颜色：\(session.sessionListTitle)")
                .popover(isPresented: Binding(get: { colorSession == session.id }, set: { if !$0 { colorSession = nil } })) {
                    colorPicker(session)
                }
            VStack(alignment: .leading, spacing: 4) {
                if let editing = coordinator.editing, editing.sessionID == session.id {
                    editingView(editing)
                } else {
                    Button { coordinator.begin(session) } label: {
                        MenuScrollingTitle(title: session.sessionListTitle, reduceMotion: reduceMotion)
                    }.buttonStyle(.plain).disabled(!model.sessionDataHealth.allowsSaving)
                        .help(session.sessionListTitle).accessibilityLabel("编辑会话标题：\(session.sessionListTitle)")
                }
                Text("\(session.persisted.projectName ?? "未知项目") · \(session.persisted.lastActivityAt?.formatted(.relative(presentation: .named)) ?? "未知时间")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(stateTitle(session.state)).font(.caption).foregroundStyle(.secondary).fixedSize()
            Toggle("参与 HUD", isOn: Binding(get: { session.persisted.isIncludedInHUD }, set: { value in
                coordinator.performAfterSaving { model.setIncluded(value, sessionID: session.id) }
            })).toggleStyle(.switch).labelsHidden().controlSize(.mini)
                .disabled(!model.sessionDataHealth.allowsSaving).accessibilityLabel("\(session.sessionListTitle) 参与 HUD")
        }.padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func editingView(_ editing: SessionTitleEditingState) -> some View {
        MenuTitleEditor(editing: editing, coordinator: coordinator, focused: $focusedTitle)
    }

    private func colorPicker(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 8) {
            ForEach(["#6C7FE8", "#E4A665", "#67B7A0", "#E16F7F", "#AC80CF", "#8192A5"], id: \.self) { color in
                Button {
                    model.requestMarkerColor(color, sessionID: session.id) { result in
                        if case .failure = result { model.markerColorErrorMessage = "会话颜色保存失败，请重试" }
                    }
                    colorSession = nil
                } label: {
                    Circle().fill(Color(nsColor: SessionMarkerView.nsColor(color))).frame(width: 19, height: 19)
                        .overlay { if session.persisted.markerColorHex == color { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
                }.buttonStyle(.plain).accessibilityLabel("选择颜色 \(color)")
            }
            Button("自定义") { colorSession = nil; model.sessionColorPanel.open(sessionID: session.id) }
        }.padding(12)
    }

    private func stateTitle(_ state: SessionRuntimeState) -> String {
        switch state { case .idle: "待机"; case .running: "执行中"; case .attention: "等待权限"; case .completed: "已完成" }
    }
}

private struct MenuTitleEditor: View {
    @ObservedObject var editing: SessionTitleEditingState
    @ObservedObject var coordinator: MenuEditingCoordinator
    var focused: FocusState<Bool>.Binding
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                TextField("会话标题", text: $editing.draft).textFieldStyle(.roundedBorder)
                    .focused(focused).disabled(editing.isSaving)
                    .onSubmit { coordinator.performAfterSaving {} }
                    .onExitCommand { coordinator.cancel() }
                if editing.session?.persisted.customTitle != nil {
                    Button("恢复默认") { coordinator.restore() }.font(.caption2).disabled(!editing.canRestore)
                }
            }
            if let message = editing.message { Text(message).font(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

private struct MenuScrollingTitle: View {
    let title: String
    let reduceMotion: Bool
    @State private var hovering = false
    @State private var textWidth: CGFloat = 0
    var body: some View {
        GeometryReader { geometry in
            Text(title).fontWeight(.medium).fixedSize().background(GeometryReader { proxy in
                Color.clear.onAppear { textWidth = proxy.size.width }.onChange(of: title) { _, _ in textWidth = proxy.size.width }
            })
            .offset(x: hovering && !reduceMotion ? -max(0, textWidth - geometry.size.width) : 0)
            .animation(hovering && !reduceMotion ? .linear(duration: max(2, Double(textWidth - geometry.size.width) / 25)) : nil, value: hovering)
            .frame(width: geometry.size.width, alignment: .leading).clipped()
        }.frame(height: 18).contentShape(Rectangle()).onHover { hovering = $0 }
    }
}
