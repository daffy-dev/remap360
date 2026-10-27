import Remap360Core
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if model.showOnboarding {
                OnboardingView()
            } else {
                MainView()
            }
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, um in model.undoManager = um }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var showInspector = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            LayerSidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            EditorCanvas()
                .inspector(isPresented: $showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 320, ideal: 360, max: 460)
                }
        }
        .toolbar { toolbar }
        .navigationTitle(model.selectedLayer?.displayName ?? "Remap360")
        .navigationSubtitle(model.isLive ? "" : (model.isDirty ? "Edited" : ""))
        .sheet(isPresented: $model.showFlashSheet) { FlashSheet() }
        .sheet(isPresented: $model.showSourceSheet) { SourceSheet() }
        .sheet(isPresented: $model.showTestPad) { TestPadView() }
        .overlay(alignment: .bottom) { ToastView() }
        .alert("Something went wrong", isPresented: Binding(get: { model.loadError != nil }, set: { if !$0 { model.loadError = nil } })) {
            Button("OK") { model.loadError = nil }
        } message: {
            Text(model.loadError ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.undoManager?.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!(model.undoManager?.canUndo ?? false))
                .help("Undo")
            Button { model.undoManager?.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!(model.undoManager?.canRedo ?? false))
                .help("Redo")
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 14) {
                SourcePicker()
                if model.isLive { ConnectionBadge() }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showTestPad = true } label: { Label("Test Pad", systemImage: "keyboard.badge.eye") }
                .help("Press keys and see exactly what your Mac receives (⌘T)")
            if model.isLive {
                if model.live.status == .ready {
                if model.live.unsaved {
                    Button { model.revertLive() } label: { Label("Revert", systemImage: "arrow.counterclockwise") }
                        .help("Throw away changes and go back to the layout saved on the keyboard")
                }
                Button { model.save() } label: {
                    Label(model.live.unsaved ? "Keep Changes" : "Saved", systemImage: model.live.unsaved ? "checkmark.circle.fill" : "checkmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.brand)
                .disabled(!model.live.unsaved || model.live.status != .ready)
                .help("Changes work instantly but are forgotten when the keyboard restarts until you keep them (⌘S)")
                }
            } else {
                Button { model.showSourceSheet = true } label: { Label("View Code", systemImage: "curlybraces") }
                    .help("Preview the keymap file that will be saved")
                    .disabled(model.document == nil)
                Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .disabled(!model.isDirty)
                    .help("Save keymap (⌘S)")
                if model.firmwareToolsEnabled {
                    Button { model.showFlashSheet = true } label: {
                        Label("Build & Flash", systemImage: "bolt.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.brand)
                    .disabled(model.document == nil)
                    .help("Build firmware and install it on your keyboard (⌘B, experimental)")
                }
            }
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                .help("Show or hide the key editor")
        }
    }
}

private struct EditorCanvas: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let update = model.firmwareUpdate {
                FirmwareBanner(update: update)
            }
            content
        }
        .background(
            ZStack {
                RadialGradient(colors: [Brand.cyan.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
                RadialGradient(colors: [Brand.emerald.opacity(0.06), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 700)
                LinearGradient(colors: [Theme.layerColor(model.selectedLayerIndex ?? 0).opacity(0.06), .clear],
                               startPoint: .top, endPoint: .center)
                    .animation(.easeInOut(duration: 0.35), value: model.selectedLayerIndex)
            }
        )
    }

    @ViewBuilder private var content: some View {
        Group {
            if model.isLive && model.live.status != .ready {
                LiveStatusView()
            } else if !model.isLive && model.document == nil {
                NoConfigView()
            } else {
                editor
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 8)

            KeyboardView()
                .padding(.horizontal, 12)
                .frame(minHeight: 300)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.leftArrow) { model.moveSelection(dx: -1, dy: 0); return .handled }
                .onKeyPress(.rightArrow) { model.moveSelection(dx: 1, dy: 0); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(dx: 0, dy: -1); return .handled }
                .onKeyPress(.downArrow) { model.moveSelection(dx: 0, dy: 1); return .handled }
                .onKeyPress(.escape) { model.selectedKey = nil; return .handled }
                .onKeyPress(.tab) { cycleLayer(); return .handled }
                .onDeleteCommand { if model.selectedKey != nil { model.setBinding(.trans, name: "Clear Key") } }
                .onCopyCommand {
                    guard let b = model.selectedBinding else { return [] }
                    return [NSItemProvider(object: b.text as NSString)]
                }
                .onPasteCommand(of: [.plainText]) { _ in model.paste() }
                .onAppear { focused = true }
                .onChange(of: model.selectedKey) { _, _ in focused = true }

            statusBar
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let i = model.selectedLayerIndex, let layer = model.selectedLayer {
                LayerBadge(index: i, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.displayName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(layerHint(i))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LayerStrip()
            }
        }
    }

    private func layerHint(_ i: Int) -> String {
        if i == 0 { return "Your default layer. Everything else sits on top of it." }
        let reach = model.activeLayers.enumerated().flatMap { li, l in
            l.bindings.enumerated().compactMap { k, b in b.layerRef == i ? (li, k, b) : nil }
        }
        guard let first = reach.first else {
            return "No key switches to this layer yet. Add a Layer key on another layer to reach it."
        }
        let key = model.activeLayers[first.0].bindings[first.1]
        let how = switch key.behavior {
        case "mo": "Hold"
        case "tog": "Toggle with"
        case "lt": "Hold"
        case "to": "Switch with"
        default: "Use"
        }
        let src = model.activeLayers[first.0].bindings[first.1].legend(in: model.context)
        return "\(how) key \(first.1) (\(src.tap)) on \(model.activeLayers[first.0].displayName). Keyboard LED shows \(Theme.layerLEDName(i).lowercased())."
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let k = model.hoveredKey ?? model.selectedKey, let li = model.selectedLayerIndex, k < model.layers[li].bindings.count {
                let b = model.layers[li].bindings[k]
                Text(b.text)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                Text(b.describe(in: model.context))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.isLive {
                Image(systemName: "bolt.fill").foregroundStyle(Brand.emerald).font(.caption)
                Text("Live: every change is on your keyboard instantly. Try it! Click **Keep Changes** when you like it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Click a key to edit it · Drag keys to swap · Tab switches layers")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            LayoutMenu()
        }
        .padding(.horizontal, 20)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func cycleLayer() {
        let active = model.activeLayers
        guard let i = model.selectedLayerIndex, !active.isEmpty else { return }
        model.selectedLayerID = active[(i + 1) % active.count].id
    }
}

/// Quick layer switcher pills shown above the keyboard.
private struct LayerStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.activeLayers.enumerated()), id: \.element.id) { i, layer in
                pill(index: i, layer: layer)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.04), in: Capsule())
    }

    private func pill(index i: Int, layer: Layer) -> some View {
        let on = layer.id == model.selectedLayerID
        let shortcut: KeyboardShortcut? = i < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command) : nil
        return Button {
            withAnimation(.snappy(duration: 0.2)) { model.selectedLayerID = layer.id }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(Theme.layerColor(i)).frame(width: 7, height: 7)
                Text(layer.displayName).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(on ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(layer.displayName) (⌘\(i + 1))")
        .keyboardShortcut(shortcut)
    }
}

private struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .padding(.bottom, 48)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct SourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("adv360.keymap").font(.headline)
                    Text(model.isDirty ? "Preview of the file after saving" : "Saved file contents")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.renderedSource, forType: .string)
                    model.flash("Copied keymap")
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(model.renderedSource)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

/// Shows which Mac keyboard layout the legends follow, with quick switches.
private struct LayoutMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Toggle("Labels follow \(model.macLayoutName) layout", isOn: Binding(
                get: { model.useMacLayoutLabels }, set: { model.useMacLayoutLabels = $0 }))
            Toggle("Show Shift and Option characters", isOn: Binding(
                get: { model.showSecondaryLegends }, set: { model.showSecondaryLegends = $0 }))
                .disabled(!model.useMacLayoutLabels)
            Divider()
            Text("Change layouts in System Settings › Keyboard › Input Sources")
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                Text(model.useMacLayoutLabels ? model.macLayoutName : "US labels")
                if model.useMacLayoutLabels && model.showSecondaryLegends {
                    Text("⇧ ⌥").foregroundStyle(.tertiary)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Key labels show what each key types on your Mac's keyboard layout")
    }
}

/// Shown when Kinesis has published firmware newer than what the user has seen.
private struct FirmwareBanner: View {
    @Environment(AppModel.self) private var model
    let update: FirmwareUpdates.Release

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.ink)
                .frame(width: 28, height: 28)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("New Advantage360 firmware from Kinesis")
                    .font(.callout.weight(.semibold))
                Text("\(update.date.formatted(date: .long, time: .omitted)) · \(update.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("What's New") { NSWorkspace.shared.open(update.url) }
            Button("Dismiss") { model.dismissFirmwareUpdate() }
                .help("Hide until the next firmware release")
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Brand.emerald.opacity(0.10))
        .overlay(alignment: .bottom) { Divider() }
    }
}
