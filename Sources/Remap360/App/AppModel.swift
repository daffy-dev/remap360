import AppKit
import Remap360Core
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    /// Where edits go: straight to the connected keyboard, or into the config file.
    enum Source: String, CaseIterable, Identifiable {
        case keyboard, file
        var id: String { rawValue }
        var title: String { self == .keyboard ? "Keyboard" : "Config File" }
    }

    var source: Source = .keyboard {
        didSet {
            guard source != oldValue else { return }
            selectedLayerID = activeLayers.first?.id
            selectedKey = nil
            undoManager?.removeAllActions()
        }
    }

    let live = LiveController()
    /// The keyboard's layers in editor form, refreshed whenever the keyboard changes.
    private(set) var liveLayers: [Layer] = []
    private var liveCustomBehaviors: [CustomBehavior] = []

    var workspace: Workspace?
    var document: KeymapDocument?
    var loadError: String?

    var selectedLayerID: Layer.ID?
    var selectedKey: Int?
    var hoveredKey: Int?
    var isDirty = false
    var lastSaved: Date?

    var showFlashSheet = false
    var showOnboarding = false
    var showTestPad = false
    var showSourceSheet = false
    var renamingLayerID: Layer.ID?
    var toast: String?

    /// Keycap legends follow the Mac's keyboard layout (e.g. Icelandic) unless turned off.
    var useMacLayoutLabels = UserDefaults.standard.object(forKey: "useMacLayoutLabels") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useMacLayoutLabels, forKey: "useMacLayoutLabels") }
    }
    private(set) var macLayout = KeyboardLayoutLabels.current()
    var keyLabels: [String: String] { useMacLayoutLabels ? (macLayout?.labels ?? [:]) : [:] }
    /// Show Shift / Option characters in the keycap corners.
    var showSecondaryLegends = UserDefaults.standard.object(forKey: "showSecondaryLegends") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSecondaryLegends, forKey: "showSecondaryLegends") }
    }
    var macLayoutName: String { macLayout?.name ?? "Mac layout" }

    /// A Kinesis firmware release newer than what the user has seen, shown as a banner.
    var firmwareUpdate: FirmwareUpdates.Release?

    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        if let ws = Workspace.saved { open(ws) }
        if document != nil { source = .file }
        live.onKeymapChanged = { [weak self] in self?.liveKeymapChanged() }
        DistributedNotificationCenter.default().addObserver(
            forName: KeyboardLayoutLabels.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.macLayout = KeyboardLayoutLabels.current() }
        }
        live.start()
        Task { await checkFirmware(manual: false) }
        // `-selectLayer 2 -selectKey 15` on the command line preselects a key (handy for screenshots).
        let defaults = UserDefaults.standard
        if let l = defaults.string(forKey: "selectLayer").flatMap(Int.init), l < layers.count { selectedLayerID = layers[l].id }
        if let k = defaults.string(forKey: "selectKey").flatMap(Int.init), k < Adv360Layout.keyCount { selectedKey = k }
        if defaults.bool(forKey: "showFlash") { showFlashSheet = true }
    }

    var isLive: Bool { source == .keyboard }

    /// Whether there's something to edit in the current source.
    var hasContent: Bool { isLive ? live.status == .ready : document != nil }

    private func liveKeymapChanged() {
        let wasReady = !liveLayers.isEmpty
        liveLayers = live.keymap?.editorLayers() ?? []
        liveCustomBehaviors = live.keymap?.customBehaviors ?? []
        if !wasReady && !liveLayers.isEmpty {
            // Keyboard just became editable: jump to it.
            source = .keyboard
            if selectedLayerID == nil || selectedLayerIndex == nil { selectedLayerID = liveLayers.first?.id }
            if let l = UserDefaults.standard.string(forKey: "selectLayer").flatMap(Int.init), l < liveLayers.count {
                selectedLayerID = liveLayers[l].id
            }
            flash("\(live.deviceName ?? "Keyboard") connected")
            // Snapshot the layout as found, so there's always a copy to go back to.
            if !live.unsaved { backupLayout() }
        }
        if isLive && selectedLayerIndex == nil { selectedLayerID = liveLayers.first?.id }
    }

    // MARK: Loading & saving

    func open(_ ws: Workspace) {
        do {
            let text = try String(contentsOf: ws.keymapURL, encoding: .utf8)
            let doc = try KeymapDocument(text: text, extraSources: ws.includeSources())
            workspace = ws
            document = doc
            ws.remember()
            source = .file
            showOnboarding = false
            selectedLayerID = doc.activeLayers.first?.id
            selectedKey = nil
            isDirty = false
            loadError = nil
            undoManager?.removeAllActions()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func reload() {
        guard let workspace else { return }
        open(workspace)
        flash("Reloaded from disk")
    }

    func closeWorkspace() {
        UserDefaults.standard.removeObject(forKey: Workspace.defaultsKey)
        workspace = nil
        document = nil
        source = .keyboard
    }

    /// Saves the config file, or commits live changes to the keyboard's memory.
    @discardableResult
    func save() -> Bool {
        if isLive {
            Task {
                do {
                    try await live.save()
                    backupLayout()
                    flash("Saved to keyboard")
                } catch {
                    loadError = error.localizedDescription
                }
            }
            return true
        }
        guard let workspace, let document else { return false }
        do {
            workspace.backupKeymap()
            let rendered = document.render()
            // Rendering only replaces the keymap node, so `document` stays valid against the new file.
            try rendered.write(to: workspace.keymapURL, atomically: true, encoding: .utf8)
            isDirty = false
            lastSaved = .now
            flash("Saved")
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    /// Throws away unsaved live changes; the keyboard goes back to its last saved layout.
    func revertLive() {
        Task {
            do {
                try await live.discard()
                undoManager?.removeAllActions()
                flash("Reverted to the saved layout")
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    var hasUnsavedChanges: Bool { isLive ? live.unsaved : isDirty }

    var renderedSource: String { document?.render() ?? "" }

    // MARK: Derived

    var layers: [Layer] { isLive ? liveLayers : (document?.layers ?? []) }
    var activeLayers: [Layer] { isLive ? liveLayers : (document?.activeLayers ?? []) }

    var selectedLayerIndex: Int? {
        guard let id = selectedLayerID else { return nil }
        return layers.firstIndex { $0.id == id }
    }

    var selectedLayer: Layer? { selectedLayerIndex.map { layers[$0] } }

    private var customBehaviors: [CustomBehavior] { isLive ? liveCustomBehaviors : (document?.customBehaviors ?? []) }

    var context: BindingContext {
        var map: [String: CustomBehavior] = [:]
        for b in customBehaviors { map[b.label] = b }
        let secondary = useMacLayoutLabels && showSecondaryLegends
        return BindingContext(layerNames: layers.map(\.displayName), customBehaviors: map, keyLabels: keyLabels,
                              shiftLabels: secondary ? (macLayout?.shifted ?? [:]) : [:],
                              optionLabels: secondary ? (macLayout?.option ?? [:]) : [:])
    }

    var macros: [CustomBehavior] { customBehaviors.filter { $0.bindingCells == 0 && $0.isMacro } }
    var holdTaps: [CustomBehavior] { customBehaviors.filter { $0.isHoldTap && $0.bindingCells == 2 } }

    var selectedBinding: KeyBinding? {
        guard let li = selectedLayerIndex, let k = selectedKey, k < layers[li].bindings.count else { return nil }
        return layers[li].bindings[k]
    }

    /// For a transparent key, what it falls through to. Lower layers other than Base are usually
    /// inactive (they're toggled or held), so Base is the honest preview.
    func effectiveBinding(layer: Int, key: Int) -> KeyBinding? {
        guard layer > 0, !layers.isEmpty, key < layers[0].bindings.count else { return nil }
        let base = layers[0].bindings[key]
        return base == .trans ? nil : base
    }

    // MARK: Editing — config file (snapshot undo)

    private func mutate(_ name: String, _ change: (inout KeymapDocument) -> Void) {
        guard var doc = document else { return }
        let before = doc.layers
        let beforeSelection = selectedLayerID
        change(&doc)
        guard doc.layers != before else { return }
        document = doc
        isDirty = true
        registerUndo(name, layers: before, selection: beforeSelection)
    }

    private func registerUndo(_ name: String, layers: [Layer], selection: Layer.ID?) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard var doc = model.document else { return }
                let current = doc.layers
                let currentSelection = model.selectedLayerID
                doc.layers = layers
                model.document = doc
                model.isDirty = true
                if let selection, layers.contains(where: { $0.id == selection }) { model.selectedLayerID = selection }
                model.registerUndo(name, layers: current, selection: currentSelection)
            }
        }
        um.setActionName(name)
    }

    // MARK: Editing — keyboard (each key change is sent immediately)

    private func liveSet(_ changes: [(key: Int, binding: KeyBinding)], layer: Int, name: String) {
        let previous = changes.map { (key: $0.key, binding: liveLayers[layer].bindings[$0.key]) }
        // Show the change right away; roll back if the keyboard refuses it.
        for c in changes { liveLayers[layer].bindings[c.key] = c.binding }
        Task {
            do {
                for c in changes { try await live.setBinding(c.binding, layer: layer, key: c.key) }
                registerLiveUndo(previous, layer: layer, name: name)
            } catch {
                liveKeymapChanged()
                flash(error.localizedDescription)
            }
        }
    }

    private func registerLiveUndo(_ changes: [(key: Int, binding: KeyBinding)], layer: Int, name: String) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.isLive, layer < model.liveLayers.count else { return }
                model.liveSet(changes, layer: layer, name: name)
            }
        }
        um.setActionName(name)
    }

    private func liveTask(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { flash(error.localizedDescription) }
        }
    }

    // MARK: Editing — shared entry points

    func setBinding(_ binding: KeyBinding, at key: Int? = nil, name: String = "Change Key") {
        guard let li = selectedLayerIndex, let k = key ?? selectedKey else { return }
        if isLive {
            guard liveLayers[li].bindings[k] != binding else { return }
            liveSet([(k, binding)], layer: li, name: name)
        } else {
            mutate(name) { $0.layers[li].bindings[k] = binding }
        }
    }

    func swapKeys(_ a: Int, _ b: Int) {
        guard let li = selectedLayerIndex, a != b else { return }
        if isLive {
            let bindings = liveLayers[li].bindings
            liveSet([(a, bindings[b]), (b, bindings[a])], layer: li, name: "Swap Keys")
        } else {
            mutate("Swap Keys") { $0.layers[li].bindings.swapAt(a, b) }
        }
    }

    func addLayer(named name: String = "New Layer", copying source: Layer? = nil) {
        let display = uniqueDisplayName(name)
        if isLive {
            liveTask { [self] in
                let index = try await live.addLayer(named: display)
                guard index < liveLayers.count else { return }
                selectedLayerID = liveLayers[index].id
                if let source {
                    let changes = source.bindings.enumerated().filter { $0.element != .trans }.map { (key: $0.offset, binding: $0.element) }
                    liveSet(changes, layer: index, name: "Duplicate Layer")
                } else {
                    renamingLayerID = liveLayers[index].id
                }
            }
            return
        }
        guard let doc = document else { return }
        var layer = Layer(
            nodeName: doc.uniqueNodeName(for: display),
            displayName: display,
            bindings: source?.bindings ?? Array(repeating: .trans, count: Adv360Layout.keyCount)
        )
        layer.extraProps = source?.extraProps.filter { !$0.hasPrefix("label") } ?? []
        let id = layer.id
        mutate(source == nil ? "Add Layer" : "Duplicate Layer") { $0.layers.insert(layer, at: $0.insertionIndex) }
        selectedLayerID = id
        renamingLayerID = source == nil ? id : nil
    }

    private func uniqueDisplayName(_ base: String) -> String {
        var name = base, n = 2
        while layers.contains(where: { $0.displayName == name }) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    func deleteLayer(_ id: Layer.ID) {
        guard let idx = layers.firstIndex(where: { $0.id == id }), activeLayers.count > 1 else { return }
        if isLive {
            liveTask { [self] in
                try await live.removeLayer(at: idx)
                if selectedLayerIndex == nil { selectedLayerID = liveLayers[max(0, idx - 1)].id }
            }
            return
        }
        mutate("Delete Layer") { d in
            d.layers.remove(at: idx)
            var mapping: [Int: Int?] = [:]
            for i in 0..<(d.layers.count + 1) { mapping[i] = i < idx ? i : (i == idx ? nil : i - 1) }
            d.remapLayerRefs(mapping)
        }
        if selectedLayerID == id { selectedLayerID = layers[max(0, min(idx, layers.count) - 1)].id }
    }

    func moveLayer(from source: IndexSet, to destination: Int) {
        if isLive {
            guard let from = source.first else { return }
            let to = destination > from ? destination - 1 : destination
            guard from != to else { return }
            liveTask { [self] in try await live.moveLayer(from: from, to: to) }
            return
        }
        guard let doc = document else { return }
        let activeCount = doc.activeLayers.count
        let dest = min(destination, activeCount)
        var order = Array(0..<doc.layers.count)
        order.move(fromOffsets: source, toOffset: dest)
        guard order != Array(0..<doc.layers.count) else { return }
        mutate("Move Layer") { d in
            d.layers = order.map { doc.layers[$0] }
            var mapping: [Int: Int?] = [:]
            for (newIndex, oldIndex) in order.enumerated() { mapping[oldIndex] = newIndex }
            d.remapLayerRefs(mapping)
        }
    }

    func renameLayer(_ id: Layer.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = layers.firstIndex(where: { $0.id == id }), layers[idx].displayName != trimmed else { return }
        if isLive {
            liveTask { [self] in try await live.renameLayer(at: idx, to: trimmed) }
            return
        }
        mutate("Rename Layer") { $0.layers[idx].displayName = trimmed }
    }

    func clearLayer(_ id: Layer.ID) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        let blank: KeyBinding = idx == 0 ? .none : .trans
        if isLive {
            let changes = liveLayers[idx].bindings.enumerated().filter { $0.element != blank }.map { (key: $0.offset, binding: blank) }
            liveSet(changes, layer: idx, name: "Clear Layer")
            return
        }
        mutate("Clear Layer") { d in d.layers[idx].bindings = d.layers[idx].bindings.map { _ in blank } }
    }

    // MARK: Firmware updates

    /// Checks at most once a day automatically; the menu command always checks.
    func checkFirmware(manual: Bool) async {
        if !manual, let last = FirmwareUpdates.lastCheck, Date.now.timeIntervalSince(last) < 20 * 3600 {
            if let seen = FirmwareUpdates.lastSeen, let cached = firmwareUpdate, cached.date <= seen { firmwareUpdate = nil }
            return
        }
        guard let latest = await FirmwareUpdates.latest() else {
            if manual { flash("Couldn't reach GitHub to check for updates") }
            return
        }
        FirmwareUpdates.lastCheck = .now
        if FirmwareUpdates.lastSeen == nil { FirmwareUpdates.lastSeen = latest.date }
        if let seen = FirmwareUpdates.lastSeen, latest.date > seen {
            firmwareUpdate = latest
        } else {
            firmwareUpdate = nil
            if manual {
                flash("Firmware is up to date (latest from Kinesis: \(latest.date.formatted(date: .abbreviated, time: .omitted)))")
            }
        }
    }

    func dismissFirmwareUpdate() {
        if let update = firmwareUpdate { FirmwareUpdates.lastSeen = update.date }
        firmwareUpdate = nil
    }

    // MARK: Layout files (export, import, backups)

    static var layoutBackupsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Remap360/Layout Backups")
    }

    var currentLayoutFile: LayoutFile {
        LayoutFile(keyboard: live.deviceName ?? "Adv360 Pro", layers: activeLayers)
    }

    /// Saved automatically whenever changes are kept on the keyboard; keeps the newest 100.
    func backupLayout() {
        guard !activeLayers.isEmpty, let data = try? currentLayoutFile.encoded() else { return }
        let fm = FileManager.default
        let dir = Self.layoutBackupsDir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: dir.appendingPathComponent("layout-\(stamp).json"))
        let old = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(100)
        for url in old { try? fm.removeItem(at: url) }
    }

    func exportLayout() {
        guard !activeLayers.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let date = Date.now.formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Adv360 Layout \(date).json"
        panel.message = "Save your whole layout. You can put it back on the keyboard any time with Import."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try currentLayoutFile.encoded().write(to: url)
            flash("Layout exported")
        } catch {
            loadError = error.localizedDescription
        }
    }

    func importLayout(from url: URL? = nil) {
        var target = url
        if target == nil {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.directoryURL = Self.layoutBackupsDir
            panel.message = "Choose a layout to put on your keyboard. You can still Revert afterwards."
            guard panel.runModal() == .OK else { return }
            target = panel.url
        }
        guard let target else { return }
        do {
            let file = try LayoutFile.decode(Data(contentsOf: target))
            apply(file)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Puts a layout file onto the keyboard (or into the config file), adding layers if needed.
    private func apply(_ file: LayoutFile) {
        if isLive {
            Task {
                var skipped = 0
                for i in file.layers.indices {
                    if i >= liveLayers.count {
                        do { _ = try await live.addLayer(named: file.layers[i].name) } catch { break }
                    } else if liveLayers[i].displayName != file.layers[i].name {
                        try? await live.renameLayer(at: i, to: file.layers[i].name)
                    }
                    let wanted = file.bindings(ofLayer: i)
                    for (k, b) in wanted.enumerated() where k < liveLayers[i].bindings.count && liveLayers[i].bindings[k] != b {
                        do { try await live.setBinding(b, layer: i, key: k) } catch { skipped += 1 }
                    }
                }
                undoManager?.removeAllActions()
                selectedLayerID = liveLayers.first?.id
                flash(skipped == 0
                      ? "Layout imported. Try it, then Keep Changes"
                      : "Imported, but \(skipped) key\(skipped == 1 ? "" : "s") use things this keyboard's firmware doesn't have")
            }
            return
        }
        guard document != nil else { return }
        mutate("Import Layout") { d in
            for (i, entry) in file.layers.enumerated() {
                let bindings = file.bindings(ofLayer: i)
                if i < d.activeLayers.count {
                    d.layers[i].displayName = entry.name
                    d.layers[i].bindings = bindings
                } else {
                    d.layers.insert(Layer(nodeName: d.uniqueNodeName(for: entry.name), displayName: entry.name, bindings: bindings),
                                    at: d.insertionIndex)
                }
            }
        }
        flash("Layout imported into the config file")
    }

    // MARK: Presets

    /// MacBook-style top row (brightness, Mission Control, media, volume) on the Q row of the Fn layer.
    static let macRow: [(key: Int, binding: KeyBinding)] = [
        (15, .kp("C_BRI_DN")), (16, .kp("C_BRI_UP")), (17, .kp("LC(UP)")), (18, .kp("LG(SPACE)")),
        (19, .kp("F11")), (20, .kp("LS(LG(N5))")),
        (22, .kp("C_PREV")), (23, .kp("C_PP")), (24, .kp("C_NEXT")),
        (25, .kp("C_MUTE")), (26, .kp("C_VOL_DN")), (27, .kp("C_VOL_UP")),
    ]

    /// The four inner "Hotkeys" on Base send ⌥1–⌥4 (workspace switching in AeroSpace and similar tools).
    static let workspaceHotkeys: [(key: Int, binding: KeyBinding)] = [
        (20, .kp("LA(N1)")), (34, .kp("LA(N2)")), (21, .kp("LA(N3)")), (39, .kp("LA(N4)")),
    ]

    func setWorkspaceHotkeys() {
        guard !layers.isEmpty else { return }
        applyPreset(Self.workspaceHotkeys, layer: 0, name: "Set Workspace Hotkeys")
        flash("Hotkeys now switch workspaces 1–4")
    }

    private func applyPreset(_ preset: [(key: Int, binding: KeyBinding)], layer li: Int, name: String) {
        selectedLayerID = layers[li].id
        selectedKey = nil
        if isLive {
            let changes = preset.filter { liveLayers[li].bindings[$0.key] != $0.binding }
            liveSet(changes, layer: li, name: name)
        } else {
            mutate(name) { d in for c in preset { d.layers[li].bindings[c.key] = c.binding } }
        }
    }

    var fnLayerIndex: Int? {
        layers.firstIndex { $0.displayName.lowercased() == "fn" } ?? (layers.count > 2 ? 2 : nil)
    }

    func addMacRow() {
        guard let li = fnLayerIndex else { flash("Couldn't find an Fn layer"); return }
        selectedLayerID = layers[li].id
        selectedKey = nil
        if isLive {
            let changes = Self.macRow.filter { liveLayers[li].bindings[$0.key] != $0.binding }
            liveSet(changes, layer: li, name: "Add Mac Row")
        } else {
            mutate("Add Mac Row") { d in for c in Self.macRow { d.layers[li].bindings[c.key] = c.binding } }
        }
        flash("Mac row added to \(layers[li].displayName). Hold Fn and try it!")
    }

    // MARK: Selection & clipboard

    func moveSelection(dx: Double, dy: Double) {
        guard let k = selectedKey else { selectedKey = 0; return }
        if let next = Adv360Layout.neighbor(of: k, dx: dx, dy: dy) { selectedKey = next }
    }

    func copySelection() {
        guard let b = selectedBinding else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(b.text, forType: .string)
        flash("Copied \(b.text)")
    }

    func paste() {
        guard selectedKey != nil, let text = NSPasteboard.general.string(forType: .string) else { return }
        let parsed = BindingParser.parse(text)
        guard parsed.count == 1 else { flash("Clipboard doesn't contain a binding"); return }
        setBinding(parsed[0], name: "Paste Key")
    }

    func flash(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }

    // MARK: Key combo hints

    struct KeyCombo {
        var hold: Int?
        var press: Int
    }

    /// Finds how to trigger a behavior from the keymap, e.g. Mod + key for `&bootloader`.
    func combo(for behavior: String, left: Bool?, in layers: [Layer]) -> KeyCombo? {
        guard let base = layers.first?.bindings else { return nil }
        for (li, layer) in layers.enumerated() {
            for (k, b) in layer.bindings.enumerated() where b.behavior == behavior {
                if let left, Adv360Layout.keys[k].isLeft != left { continue }
                if li == 0 { return KeyCombo(hold: nil, press: k) }
                if let hold = base.firstIndex(where: { ($0.behavior == "mo" || $0.behavior == "lt") && $0.layerRef == li }) {
                    return KeyCombo(hold: hold, press: k)
                }
            }
        }
        return nil
    }

    func bootloaderCombo(left: Bool) -> KeyCombo? {
        combo(for: "bootloader", left: left, in: document?.activeLayers ?? activeLayers)
    }

    /// How to unlock live editing. The keyboard can't tell us while locked, so use the config file
    /// if we have one, otherwise the stock Kinesis layout (hold Mod, press Esc).
    var unlockCombo: KeyCombo {
        combo(for: "studio_unlock", left: nil, in: document?.activeLayers ?? []) ?? KeyCombo(hold: 7, press: 28)
    }
}
