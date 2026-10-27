import AppKit
import SwiftUI

@main
struct Remap360App: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Remap360", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 640)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1440, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.hasUnsavedChanges)
            }
            CommandGroup(replacing: .importExport) {
                Button("Export Layout…") { model.exportLayout() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!model.hasContent)
                Button("Import Layout…") { model.importLayout() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(!model.hasContent)
                Button("Show Layout Backups") {
                    try? FileManager.default.createDirectory(at: AppModel.layoutBackupsDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AppModel.layoutBackupsDir)
                }
            }
            CommandGroup(after: .toolbar) {
                Toggle("Key Labels Follow \(model.macLayoutName) Layout", isOn: Binding(
                    get: { model.useMacLayoutLabels }, set: { model.useMacLayoutLabels = $0 }))
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
            CommandMenu("Keyboard") {
                Button("Build & Flash…") { model.showFlashSheet = true }
                    .keyboardShortcut("b")
                    .disabled(model.document == nil)
                Button("View Keymap Code") { model.showSourceSheet = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(model.document == nil)
                Divider()
                Button("Check for Firmware Updates") { Task { await model.checkFirmware(manual: true) } }
                Button("Test Pad…") { model.showTestPad = true }
                    .keyboardShortcut("t")
                Button("Add Mac Row to Fn Layer") { model.addMacRow() }
                    .disabled(!model.hasContent)
                Button("Set Hotkeys to ⌥1–⌥4 (Workspaces)") { model.setWorkspaceHotkeys() }
                    .disabled(!model.hasContent)
                Divider()
                Button("New Layer") { model.addLayer() }
                    .disabled(model.document == nil)
                Button("Reload from Disk") { model.reload() }
                    .disabled(model.workspace == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running from `swift run` starts us as a background process; make it a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
