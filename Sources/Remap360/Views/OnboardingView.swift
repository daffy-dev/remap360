import Remap360Core
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var cloning = false
    @State private var cloneLog = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            ZStack {
                LinearGradient(colors: [Brand.night, Brand.ink], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Brand.cyan.opacity(0.32), .clear], center: UnitPoint(x: 0.2, y: 0.1),
                               startRadius: 0, endRadius: 700)
                RadialGradient(colors: [Brand.lime.opacity(0.14), .clear], center: UnitPoint(x: 0.9, y: 0.95),
                               startRadius: 0, endRadius: 650)
            }
            .ignoresSafeArea()

            VStack(spacing: 28) {
                LogoMark()
                    .frame(width: 132, height: 132)
                    .shadow(color: Brand.emerald.opacity(0.5), radius: 30)

                VStack(spacing: 10) {
                    HStack(spacing: 0) {
                        Text("Remap").foregroundStyle(.white)
                        Text("360").foregroundStyle(Brand.horizontal)
                    }
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    Text("Set up the config file. You only need it for big changes like new macros\nand firmware updates. Everyday remapping happens live over USB.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }

                KeyboardSilhouette()
                    .frame(width: 460, height: 130)
                    .opacity(0.8)

                VStack(spacing: 12) {
                    Button(action: clone) {
                        HStack(spacing: 10) {
                            if cloning { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.circle.fill") }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cloning ? "Downloading…" : "Start with the official Kinesis config").font(.headline)
                                Text("Downloads Adv360-Pro-ZMK into Documents/Remap360").font(.caption).opacity(0.8)
                            }
                        }
                        .frame(width: 360, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(OnboardingButtonStyle(prominent: true))
                    .disabled(cloning)

                    Button(action: chooseFolder) {
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Open my existing config folder…").font(.headline)
                                Text("Your clone or fork of Adv360-Pro-ZMK").font(.caption).opacity(0.7)
                            }
                        }
                        .frame(width: 360, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(OnboardingButtonStyle(prominent: false))
                    .disabled(cloning)
                }

                if cloning || !cloneLog.isEmpty {
                    Text(cloneLog)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .frame(width: 420)
                }
                Button("Back") { model.showOnboarding = false }
                    .buttonStyle(.link)
                    .foregroundStyle(.white.opacity(0.6))
                    .disabled(cloning)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 460)
                }
            }
            .padding(40)
        }
        .frame(minWidth: 760, minHeight: 600)
        .environment(\.colorScheme, .dark)
    }

    private func clone() {
        error = nil
        let dest = Workspace.defaultLocation
        if Workspace.isValid(dest) {
            model.open(Workspace(root: dest))
            return
        }
        cloning = true
        Task {
            do {
                let ws = try await Workspace.clone(to: dest) { line in
                    Task { @MainActor in cloneLog = line }
                }
                model.open(ws)
            } catch {
                self.error = error.localizedDescription
            }
            cloning = false
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Config"
        panel.message = "Choose your Adv360-Pro-ZMK folder (it contains config/adv360.keymap)"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        // Accept the config folder itself too.
        if !Workspace.isValid(url), Workspace.isValid(url.deletingLastPathComponent()) { url = url.deletingLastPathComponent() }
        if Workspace.isValid(url) {
            model.open(Workspace(root: url))
        } else {
            error = "That folder doesn't contain config/adv360.keymap."
        }
    }
}

/// Decorative outline of the keyboard used on the welcome screen.
private struct KeyboardSilhouette: View {
    @State private var phase = 0.0

    var body: some View {
        GeometryReader { geo in
            let b = Adv360Layout.bounds
            let s = min(geo.size.width / b.width, geo.size.height / b.height)
            let ox = (geo.size.width - b.width * s) / 2 - b.minX * s
            let oy = (geo.size.height - b.height * s) / 2 - b.minY * s
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, _ in
                    for key in Adv360Layout.keys {
                        let c = key.center
                        let rect = CGRect(x: -key.w / 2 + 6, y: -key.h / 2 + 6, width: key.w - 12, height: key.h - 12)
                        let tr = CGAffineTransform(translationX: ox + c.x * s, y: oy + c.y * s)
                            .scaledBy(x: s, y: s).rotated(by: key.degrees * .pi / 180)
                        let path = Path(roundedRect: rect, cornerRadius: 16).applying(tr)
                        let wave = (sin(t * 1.6 - c.x / 160 + c.y / 300) + 1) / 2
                        let palette = [Brand.cyan, Brand.emerald, Brand.lime]
                        let color = palette[Int((c.x / 1800) * 2.99)]
                        ctx.fill(path, with: .color(color.opacity(0.06 + wave * 0.4)))
                        ctx.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 1)
                    }
                }
            }
        }
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Brand.ink : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Brand.horizontal) : AnyShapeStyle(Color.white.opacity(0.08)))
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(prominent ? 0.25 : 0.12)))
            .shadow(color: prominent ? Brand.emerald.opacity(0.45) : .clear, radius: 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
