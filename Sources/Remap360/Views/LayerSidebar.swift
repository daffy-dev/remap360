import Remap360Core
import SwiftUI

struct LayerSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: Layer?

    var body: some View {
        @Bindable var model = model
        let active = model.activeLayers
        let reserved = model.layers.filter(\.isReserved).count

        VStack(spacing: 0) {
            Wordmark(height: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
            List(selection: $model.selectedLayerID) {
                Section {
                    ForEach(Array(active.enumerated()), id: \.element.id) { i, layer in
                        LayerRow(index: i, layer: layer, usage: usage(of: i))
                            .tag(layer.id)
                            .contextMenu { menu(for: layer, index: i) }
                    }
                    .onMove { model.moveLayer(from: $0, to: $1) }
                } header: {
                    Text("Layers")
                } footer: {
                    if reserved > 0 {
                        Text("\(reserved) more slots reserved for ZMK Studio")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 8) {
                Button { model.addLayer() } label: {
                    Label("New Layer", systemImage: "plus")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if model.isLive {
                LiveFooter()
            } else if let ws = model.workspace {
                WorkspaceFooter(workspace: ws)
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Layer", role: .destructive) {
                if let l = pendingDelete { model.deleteLayer(l.id) }
                pendingDelete = nil
            }
        } message: {
            Text("Keys that switch to this layer become pass-through, and layers above it are renumbered. You can undo this.")
        }
    }

    /// Number of keys in other layers that reach this layer.
    private func usage(of index: Int) -> Int {
        model.activeLayers.reduce(0) { $0 + $1.bindings.filter { $0.layerRef == index }.count }
    }

    @ViewBuilder
    private func menu(for layer: Layer, index: Int) -> some View {
        Button("Rename") { model.renamingLayerID = layer.id }
        Button("Duplicate") { model.addLayer(named: layer.displayName + " copy", copying: layer) }
        Button(index == 0 ? "Disable All Keys" : "Clear (all pass-through)") { model.clearLayer(layer.id) }
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = layer }
            .disabled(model.activeLayers.count <= 1)
    }
}

private struct LayerRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let layer: Layer
    let usage: Int
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 10) {
            LayerBadge(index: index, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                if model.renamingLayerID == layer.id {
                    TextField("Layer name", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($editing)
                        .onSubmit(commit)
                        .onAppear { draft = layer.displayName; editing = true }
                        .onChange(of: editing) { _, now in if !now { commit() } }
                        .onExitCommand { model.renamingLayerID = nil }
                } else {
                    Text(layer.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .onTapGesture(count: 2) { model.renamingLayerID = layer.id }
        .simultaneousGesture(TapGesture().onEnded { model.selectedLayerID = layer.id })
    }

    private var subtitle: String {
        let defined = layer.bindings.filter { $0 != .trans && $0 != .none }.count
        var parts: [String] = []
        if index == 0 { parts.append("Default") } else { parts.append("\(defined) key\(defined == 1 ? "" : "s")") }
        if index > 0 && usage == 0 { parts.append("unreachable") }
        parts.append("LED \(Theme.layerLEDName(index).lowercased())")
        return parts.joined(separator: " · ")
    }

    private func commit() {
        guard model.renamingLayerID == layer.id else { return }
        model.renameLayer(layer.id, to: draft)
        model.renamingLayerID = nil
    }
}

private struct WorkspaceFooter: View {
    @Environment(AppModel.self) private var model
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(workspace.root.lastPathComponent).font(.caption.weight(.medium)).lineLimit(1)
                Text(model.isDirty ? "Unsaved changes" : (model.lastSaved.map { "Saved \($0.formatted(date: .omitted, time: .shortened))" } ?? "Up to date"))
                    .font(.caption2)
                    .foregroundStyle(model.isDirty ? .orange : .secondary)
            }
            Spacer()
            Menu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([workspace.keymapURL]) }
                Button("Open Keymap in Editor") { NSWorkspace.shared.open(workspace.keymapURL) }
                Button("Reload from Disk") { model.reload() }
                Divider()
                Button("Open Backups Folder") {
                    try? FileManager.default.createDirectory(at: Workspace.backupsDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Workspace.backupsDir)
                }
                Button("Switch Config Folder…") { model.closeWorkspace() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct LiveFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard.fill").foregroundStyle(model.live.status == .ready ? Brand.emerald : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.live.deviceName ?? "No keyboard").font(.caption.weight(.medium)).lineLimit(1)
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(model.live.unsaved ? Brand.amber : .secondary)
            }
            Spacer()
            if model.live.isConnected {
                Menu {
                    Button("Revert to Saved Layout") { model.revertLive() }
                        .disabled(!model.live.unsaved)
                    Button("Reload from Keyboard") { Task { await model.live.load() } }
                    Divider()
                    Button("Disconnect") { model.live.disconnect() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var status: String {
        switch model.live.status {
        case .searching: "Plug in with USB"
        case .connecting, .loading: "Connecting…"
        case .locked: "Locked"
        case .ready: model.live.unsaved ? "Changes not kept yet" : "All changes kept"
        }
    }
}
