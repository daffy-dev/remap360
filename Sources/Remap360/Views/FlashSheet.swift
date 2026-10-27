import Remap360Core
import SwiftUI

@MainActor
@Observable
final class FlashSession {
    enum Step: Int, CaseIterable, Comparable {
        case save, build, waitLeft, flashLeft, waitRight, flashRight, done

        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .save: "Save keymap"
            case .build: "Build firmware"
            case .waitLeft: "Connect left half in flash mode"
            case .flashLeft: "Install on left half"
            case .waitRight: "Connect right half in flash mode"
            case .flashRight: "Install on right half"
            case .done: "Done"
            }
        }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case left, both, buildOnly
        var id: String { rawValue }
    }

    var mode: Mode = .left
    var step: Step?
    var error: String?
    var log: [String] = []
    var startedBuild: Date?
    var firmware: BuiltFirmware?
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { step != nil && step != .done && error == nil }

    var steps: [Step] {
        switch mode {
        case .left: [.save, .build, .waitLeft, .flashLeft, .done]
        case .both: [.save, .build, .waitLeft, .flashLeft, .waitRight, .flashRight, .done]
        case .buildOnly: [.save, .build, .done]
        }
    }

    func start(model: AppModel) {
        guard let ws = model.workspace else { return }
        error = nil
        log = []
        task = Task {
            do {
                step = .save
                if model.isDirty { guard model.save() else { throw FlashError.saveFailed } }

                step = .build
                startedBuild = .now
                let fw = try await FirmwareBuilder.build(ws, right: mode == .both) { line in
                    Task { @MainActor [weak self] in self?.append(line) }
                }
                firmware = fw

                if mode != .buildOnly, let left = fw.left {
                    step = .waitLeft
                    let vol = try await Flasher.waitForBootloader()
                    step = .flashLeft
                    try await Flasher.flash(left, to: vol)
                }
                if mode == .both, let right = fw.right {
                    // Let the left drive unmount fully before looking for the right one.
                    try await Task.sleep(for: .seconds(2))
                    step = .waitRight
                    let vol = try await Flasher.waitForBootloader()
                    step = .flashRight
                    try await Flasher.flash(right, to: vol)
                }
                step = .done
            } catch is CancellationError {
                step = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 600 { log.removeFirst(log.count - 600) }
    }

    enum FlashError: LocalizedError {
        case saveFailed
        var errorDescription: String? { "Couldn't save the keymap." }
    }
}

struct FlashSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session = FlashSession()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if session.step == nil && session.error == nil {
                    ConfigureView(session: session)
                } else {
                    ProgressPane(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 720, height: 600)
        .onDisappear { session.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Brand.ink)
                .frame(width: 36, height: 36)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Build & Flash").font(.title3.weight(.semibold))
                Text("Compiles your keymap with Docker and installs it over USB.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if let fw = session.firmware?.left {
                Button("Show Firmware in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fw])
                }
                .buttonStyle(.link)
            }
            Spacer()
            if session.step == nil && session.error == nil {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(session.mode == .buildOnly ? "Build" : "Build & Flash") { session.start(model: model) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.brand)
            } else if session.isRunning {
                Button("Cancel") { session.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            } else if session.error != nil {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Try Again") { session.start(model: model) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.brand)
            } else {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.brand)
            }
        }
        .padding(16)
    }
}

private struct ConfigureView: View {
    @Bindable var session: FlashSession
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What do you want to update?").font(.headline)
                ModeCard(session: session, mode: .left, symbol: "rectangle.lefthalf.inset.filled",
                         title: "Left half only", badge: "Recommended",
                         detail: "Keymap changes live on the left half. Fastest option.")
                ModeCard(session: session, mode: .both, symbol: "rectangle.split.2x1.fill",
                         title: "Both halves", badge: nil,
                         detail: "Needed after a firmware update or when changing right-side settings.")
                ModeCard(session: session, mode: .buildOnly, symbol: "hammer.fill",
                         title: "Build only", badge: nil,
                         detail: "Produce .uf2 files in the firmware folder without flashing.")

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First build takes a while").font(.callout.weight(.semibold))
                        Text("Docker downloads the ZMK toolchain once (a few GB, ~5–10 min). Later builds take about a minute. If you've edited keys with ZMK Studio, those changes are stored on the keyboard and override flashed ones. Use “Restore Stock Settings” in Studio to clear them.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(24)
        }
    }
}

private struct ModeCard: View {
    @Bindable var session: FlashSession
    let mode: FlashSession.Mode
    let symbol: String
    let title: String
    let badge: String?
    let detail: String

    var body: some View {
        let on = session.mode == mode
        Button { session.mode = mode } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Theme.accent : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.body.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(on ? Theme.accent : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? Theme.accent.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(on ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressPane: View {
    let session: FlashSession

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(session.steps, id: \.self) { step in
                    StepRow(step: step, session: session)
                }
                Spacer()
            }
            .frame(width: 230)
            .padding(.vertical, 20)
            .padding(.leading, 20)

            Divider()

            StepDetail(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
        }
    }
}

private struct StepRow: View {
    let step: FlashSession.Step
    let session: FlashSession

    var body: some View {
        let state = stateOf(step)
        HStack(spacing: 10) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .active:
                    ProgressView().controlSize(.small)
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                case .pending:
                    Image(systemName: "circle").foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 16))
            .frame(width: 20, height: 20)
            Text(step.title)
                .font(.callout.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(state == .pending ? .secondary : .primary)
        }
        .padding(.vertical, 8)
    }

    enum RowState { case pending, active, done, failed }

    private func stateOf(_ s: FlashSession.Step) -> RowState {
        guard let current = session.step else { return .pending }
        if s == .done { return current == .done ? .done : .pending }
        if s < current || current == .done { return .done }
        if s == current { return session.error == nil ? .active : .failed }
        return .pending
    }
}

private struct StepDetail: View {
    @Environment(AppModel.self) private var model
    let session: FlashSession

    var body: some View {
        if let error = session.error {
            VStack(alignment: .leading, spacing: 12) {
                Label("That didn't work", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
                Text(error)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !session.log.isEmpty { LogView(lines: session.log) }
            }
        } else {
            switch session.step {
            case .save, .build, nil:
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Building firmware…").font(.title3.weight(.semibold))
                        Spacer()
                        if let start = session.startedBuild {
                            Text(start, style: .timer)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(session.log.last(where: { $0.hasPrefix("▸") }) ?? "Starting Docker…")
                        .font(.callout).foregroundStyle(.secondary)
                    LogView(lines: session.log)
                }
            case .waitLeft, .waitRight:
                WaitForBootloader(left: session.step == .waitLeft)
            case .flashLeft, .flashRight:
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView().controlSize(.large)
                    Text("Installing firmware…").font(.title3.weight(.semibold))
                    Text("Don't unplug the keyboard. It'll restart by itself when finished.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            case .done:
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Brand.gradient)
                        .symbolEffect(.bounce, value: session.step)
                    Text(session.mode == .buildOnly ? "Firmware built" : "Your keyboard is updated")
                        .font(.title2.weight(.semibold))
                    Text(session.mode == .buildOnly
                         ? "The .uf2 files are in the firmware folder."
                         : "Start typing. Your new layout is live.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct WaitForBootloader: View {
    @Environment(AppModel.self) private var model
    let left: Bool
    @State private var pulse = false

    var body: some View {
        let combo = model.bootloaderCombo(left: left)
        VStack(alignment: .leading, spacing: 14) {
            Text("Put the \(left ? "left" : "right") half in flash mode")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                if left {
                    instruction(1, "Connect the left half to this Mac with a USB cable.")
                } else {
                    instruction(1, "Unplug the left half, then connect the right half with USB.")
                }
                if let combo {
                    let ctx = model.context
                    let press = model.activeLayers.first { $0.bindings.indices.contains(combo.press) }.map { _ in "key \(combo.press)" } ?? ""
                    if let hold = combo.hold {
                        let holdName = model.activeLayers[0].bindings[hold].legend(in: ctx).tap
                        instruction(2, "Hold **\(holdName)** (key \(hold)) and press the highlighted \(press) on the \(left ? "left" : "right") half.")
                    } else {
                        instruction(2, "Press the highlighted \(press).")
                    }
                } else {
                    instruction(2, "Double-tap the reset button on the \(left ? "left" : "right") half with a paperclip.")
                }
            }

            if let combo {
                KeyboardView(highlighted: Set([combo.hold, combo.press].compactMap { $0 }), interactive: false, layerIndex: 0)
                    .frame(height: 170)
                    .allowsHitTesting(false)
                Text("Or double-tap the reset button on the back of that half.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulse ? 1.4 : 0.8)
                    .opacity(pulse ? 0.4 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(), value: pulse)
                Text("Waiting for the keyboard to appear as a USB drive…")
                    .font(.callout.weight(.medium))
            }
            .onAppear { pulse = true }
        }
    }

    private func instruction(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.15), in: Circle())
                .foregroundStyle(Theme.accent)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("▸") || line.hasPrefix("✓") ? Color.white : Color.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(10)
                .textSelection(.enabled)
            }
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: lines.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
        }
    }
}
