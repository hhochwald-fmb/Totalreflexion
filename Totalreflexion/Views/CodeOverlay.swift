import AppKit
import SwiftUI

/// Shows the AirPlay code large on every screen (including a projector) while an iPad asks for it,
/// like an Apple TV does. Clicks pass through.
@MainActor
final class CodeOverlay {
    private var panels: [NSPanel] = []
    private var shownCode: String?

    func show(_ code: String?) {
        guard code != shownCode else { return }
        shownCode = code
        panels.forEach { $0.orderOut(nil) }
        panels = []
        guard let code else { return }
        for screen in NSScreen.screens {
            let size = NSSize(width: 560, height: 320)
            let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                               width: size.width, height: size.height)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            // Above full-screen views and the full-screen device level.
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: CodeCard(code: code))
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }
}

private struct CodeCard: View {
    let code: String

    var body: some View {
        VStack(spacing: 12) {
            Label("AirPlay-Code", systemImage: "airplayvideo")
                .font(.title2.weight(.semibold))
            Text(code.map(String.init).joined(separator: " "))
                .font(.system(size: 104, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("Diesen Code auf dem iPad eingeben")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
