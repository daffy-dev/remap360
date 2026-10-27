import Remap360Core
import SwiftUI

/// Toolbar switch between editing the keyboard live and editing the config file.
struct SourcePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Edit", selection: $model.source) {
            Text("Keyboard").tag(AppModel.Source.keyboard)
            Text("Config File").tag(AppModel.Source.file)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 230)
        .help("Keyboard: changes apply instantly over USB. Config File: edit the keymap file and flash it.")
    }
}

/// Small colored dot + text describing the keyboard connection.
struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let (color, text) = describe()
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func describe() -> (Color, String) {
        switch model.live.status {
        case .searching: (.secondary.opacity(0.5), "No keyboard")
        case .connecting: (Brand.amber, "Connecting…")
        case .locked: (Brand.amber, "\(model.live.deviceName ?? "Keyboard") · locked")
        case .loading: (Brand.amber, "Reading layout…")
        case .ready: (Brand.emerald, model.live.unsaved ? "Live · not saved yet" : "Live · \(model.live.deviceName ?? "Keyboard")")
        }
    }
}

/// Shown in place of the keyboard when live editing isn't possible yet.
struct LiveStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            switch model.live.status {
            case .searching:
                searching
            case .connecting, .loading:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(model.live.status == .connecting ? "Connecting to your keyboard…" : "Reading your layout…")
                        .font(.title3.weight(.semibold))
                }
            case .locked:
                locked
            case .ready:
                EmptyView()
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searching: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Brand.cyan.opacity(0.12)).frame(width: 110, height: 110)
                Image(systemName: "cable.connector")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Brand.gradient)
            }
            VStack(spacing: 8) {
                Text("Plug in your keyboard")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Connect the **left half** to this Mac with a USB cable.\nRemap360 finds it automatically, so there's nothing else to do.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 10) {
                hint("cable.connector.horizontal", "Use a data cable. Some charging-only cables don't carry data.")
                hint("xmark.app", "Quit ZMK Studio if it's open. Only one app can talk to the keyboard at a time.")
                hint("arrow.down.circle", "Still not found? Your keyboard may need Kinesis' one-time firmware update that turns on live editing (it's called “Clique” firmware).")
                Link("How to update (kinesis-ergo.com) →", destination: URL(string: "https://kinesis-ergo.com/360p-clique-upgrade/")!)
                    .font(.callout.weight(.medium))
                    .padding(.leading, 30)
            }
            .frame(maxWidth: 520)
            .padding(16)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var locked: some View {
        let combo = model.unlockCombo
        var labels: [Int: String] = [combo.press: "Esc"]
        if let hold = combo.hold { labels[hold] = "Mod" }
        if combo.press != 28 { labels[combo.press] = "Unlock" }
        return VStack(spacing: 20) {
            ZStack {
                Circle().fill(Brand.amber.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "lock.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Brand.amber)
            }
            VStack(spacing: 8) {
                Text("Unlock your keyboard")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(combo.hold != nil
                     ? "\(model.live.deviceName ?? "Your keyboard") is connected. For safety it only accepts changes after you **hold Mod and press Esc**, the keys highlighted below."
                     : "\(model.live.deviceName ?? "Your keyboard") is connected. Press the highlighted unlock key to allow changes.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }
            KeyboardView(highlighted: Set([combo.hold, combo.press].compactMap { $0 }), interactive: false, labels: labels)
                .frame(maxWidth: 760, maxHeight: 280)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for unlock…").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
        }
    }

    private func hint(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Brand.cyan).frame(width: 20)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shown in Config File mode when no config folder is open yet.
struct NoConfigView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(Brand.gradient)
            Text("No config file open")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("You only need the config file for things live editing can't do, like adding new macros.\nIt's also where firmware updates are built from.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Set Up Config File…") { model.showOnboarding = true }
                .buttonStyle(.brand)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
