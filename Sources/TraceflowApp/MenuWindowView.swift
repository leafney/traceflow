import AppKit
import SwiftUI
import TraceflowCore

@MainActor
final class MenuEditingCoordinator: ObservableObject {
    @Published var editing: SessionTitleEditingState?
    @Published var retainedSession: SessionSnapshot?
    @Published var focusGeneration = 0
    @Published private(set) var saving = false
    private var pendingAction: (() -> Void)?
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
            performAfterSaving()
        }
    }

    func performAfterSaving(_ action: (() -> Void)? = nil) {
        blurTask?.cancel()
        guard let editing else { action?(); return }
        guard !saving else { if pendingAction == nil { pendingAction = action }; return }
        if editing.draft == (editing.session?.effectiveConversationTitle ?? "") {
            cancel(); action?(); return
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
        guard let editing, !saving, editing.unavailableMessage == nil else { return }
        if editing.session?.persisted.customTitle == nil { cancel(); return }
        saving = true
        Task {
            let success = await editing.restore()
            saving = false
            if success {
                let next = pendingAction
                cancel()
                next?()
            } else { pendingAction = nil; focusGeneration += 1 }
        }
    }
}

struct MenuWindowView: View {
    @ObservedObject var model: AppModel
    unowned let controller: MenuWindowController
    @StateObject private var coordinator: MenuEditingCoordinator
    @State private var colorSession: String?
    @State private var openSelection: String?
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
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Traceflow").font(.headline)
                    Text("会话动态 一目了然").font(.caption).foregroundStyle(.secondary)
                }
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
                    selectionMenu("HUD 布局", value: model.hudLayoutMode.menuTitle) {
                        ForEach(Array(HUDLayoutMode.allCases.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            Button { openSelection = nil; coordinator.performAfterSaving { model.hudLayoutMode = item } } label: { selectionOption(item.menuTitle, selected: item == model.hudLayoutMode) }
                        }
                    }
                    selectionMenu("HUD 显示模式", value: model.hudDisplayStyle.menuTitle) {
                        ForEach(Array(HUDDisplayStyle.allCases.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            Button { openSelection = nil; coordinator.performAfterSaving { model.hudDisplayStyle = item } } label: { selectionOption(item.menuTitle, selected: item == model.hudDisplayStyle) }
                        }
                    }
                }
                if !model.sessionDataHealth.allowsSaving {
                    HStack {
                        Text("会话数据暂时无法保存，请在设置中修复").font(.caption).foregroundStyle(.red)
                        Spacer()
                        Button("设置") { coordinator.performAfterSaving { controller.closeImmediately(); model.openSettingsWindow() } }.font(.caption)
                    }.padding(8)
                }
                HStack {
                    Text("活跃会话").font(.headline)
                    Text("· 最近 10 分钟").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.recentSessions.count) 个会话").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Color.primary.opacity(0.06), in: Capsule())
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
                    }.frame(maxWidth: .infinity, minHeight: sessions.isEmpty ? 198 : 0)
                }
                .frame(maxHeight: 198)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            HStack { Spacer(); Button("退出 Traceflow") { coordinator.performAfterSaving { NSApplication.shared.terminate(nil) } }.buttonStyle(.plain).keyboardShortcut("q", modifiers: .command) }
                .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
        .coordinateSpace(name: "menu")
        .onPreferenceChange(EditorFrameKey.self) { rect in
            controller.editingArea = rect.map { CGRect(x: $0.minX, y: controller.contentHeight - $0.maxY, width: $0.width, height: $0.height) }
        }
        .onAppear {
            controller.requestClose = { coordinator.performAfterSaving { controller.closeImmediately() } }
            controller.didClose = { colorSession = nil; openSelection = nil; controller.editingArea = nil }
            controller.clickedOutsideEditor = { coordinator.scheduleBlurSave() }
            controller.updateHeight(sessionCount: sessions.count)
        }
        .onExitCommand {
            if coordinator.editing != nil { coordinator.cancel() } else { controller.requestDismiss() }
        }
        .onChange(of: coordinator.editing?.sessionID) { _, id in focusedTitle = id != nil }
        .onChange(of: coordinator.focusGeneration) { _, _ in
            controller.restoreEditingFocus()
            focusedTitle = true
        }
        .onChange(of: sessions.count) { _, count in controller.updateHeight(sessionCount: count) }
        .onChange(of: colorSession) { _, id in controller.isColorPopoverVisible = id != nil || openSelection != nil }
        .onChange(of: openSelection) { _, value in controller.isColorPopoverVisible = value != nil || colorSession != nil }
        .onChange(of: focusedTitle) { _, focused in
            if !focused, coordinator.editing != nil { coordinator.scheduleBlurSave() }
        }
    }

    private func selectionMenu<Content: View>(_ title: String, value: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        Button { coordinator.performAfterSaving { openSelection = title } } label: {
            HStack(spacing: 3) {
                Text(title).lineLimit(1)
                Spacer(minLength: 2)
                Text(value).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.font(.system(size: 12)).padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 38)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.16)))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .popover(isPresented: Binding(get: { openSelection == title }, set: { if !$0 { openSelection = nil } })) {
                VStack(alignment: .leading, spacing: 2) { content() }
                    .buttonStyle(.plain).padding(6).frame(minWidth: 140)
            }
    }

    private func selectionOption(_ title: String, selected: Bool) -> some View {
        HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark") } }
            .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
    }

    private func checkButton(_ title: String, value: Binding<Bool>) -> some View {
        Button { coordinator.performAfterSaving { value.wrappedValue.toggle() } } label: {
            HStack { Text(title); Spacer(); if value.wrappedValue { Image(systemName: "checkmark") } }
                .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 38)
                .foregroundStyle(value.wrappedValue ? Color.accentColor : Color.primary)
                .background(value.wrappedValue ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(value.wrappedValue ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.10)))
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
            HStack(spacing: 4) {
                Circle().fill(session.state == .attention ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(stateTitle(session.state))
            }.font(.caption).foregroundStyle(.secondary).fixedSize()
            Toggle("参与 HUD", isOn: Binding(get: { session.persisted.isIncludedInHUD }, set: { value in
                coordinator.performAfterSaving { model.setIncluded(value, sessionID: session.id) }
            })).toggleStyle(.switch).labelsHidden().controlSize(.mini)
                .disabled(!model.sessionDataHealth.allowsSaving).accessibilityLabel("\(session.sessionListTitle) 参与 HUD")
        }.padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func editingView(_ editing: SessionTitleEditingState) -> some View {
        MenuTitleEditor(editing: editing, coordinator: coordinator, focused: $focusedTitle)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: EditorFrameKey.self, value: proxy.frame(in: .named("menu")))
            })
    }

    private func colorPicker(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 8) {
            ForEach(SessionColorOptions.options(sessionID: session.id, currentColor: session.persisted.markerColorHex), id: \.hex) { option in
                let color = option.hex
                Button {
                    model.markerColorErrorMessage = nil
                    model.requestMarkerColor(color, sessionID: session.id) { result in
                        if case .failure = result { model.markerColorErrorMessage = "会话颜色保存失败，请重试" }
                        else if model.markerColorErrorMessage == "会话颜色保存失败，请重试" { model.markerColorErrorMessage = nil }
                    }
                    colorSession = nil
                } label: {
                    Circle().fill(Color(nsColor: SessionMarkerView.nsColor(color))).frame(width: 19, height: 19)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1))
                        .overlay { if option.isSelected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(SessionColorOptions.usesDarkSelectionMark(for: color) ? Color.black : Color.white) } }
                }.buttonStyle(.plain).accessibilityLabel("选择颜色 \(color)")
                    .accessibilityValue(option.isSelected ? "已选择" : "未选择")
            }
            Button("自定义") { colorSession = nil; controller.openColorPanel(sessionID: session.id) }
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
                    .onSubmit { coordinator.performAfterSaving() }
                    .onExitCommand { coordinator.cancel() }
                Button("恢复默认") { coordinator.restore() }
                    .font(.caption2).fixedSize().disabled(editing.isSaving || editing.unavailableMessage != nil)
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

private struct EditorFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}
