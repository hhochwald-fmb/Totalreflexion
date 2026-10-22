import SwiftUI

enum HelpTopic: String, CaseIterable, Identifiable {
    case overview
    case connect
    case views
    case mainWindow
    case presentation
    case floating
    case devices
    case appearance
    case shortcuts
    case troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Was kann Totalreflexion?"
        case .connect: "iPad verbinden"
        case .views: "Die drei Ansichten"
        case .mainWindow: "Hauptfenster"
        case .presentation: "Präsentation"
        case .floating: "Eigene Fenster"
        case .devices: "Geräte verwalten"
        case .appearance: "Rahmen & Aussehen"
        case .shortcuts: "Tastenkürzel & Maus"
        case .troubleshooting: "Probleme lösen"
        }
    }

    var icon: String {
        switch self {
        case .overview: "sparkles"
        case .connect: "airplayvideo"
        case .views: "rectangle.3.group"
        case .mainWindow: "square.grid.2x2"
        case .presentation: "play.rectangle.on.rectangle"
        case .floating: "macwindow.on.rectangle"
        case .devices: "list.bullet.rectangle"
        case .appearance: "ipad"
        case .shortcuts: "keyboard"
        case .troubleshooting: "wrench.and.screwdriver"
        }
    }
}

/// Which help page is shown; shared so any window can open the help at a specific topic.
@MainActor
@Observable
final class HelpNavigator {
    var topic: HelpTopic = .overview
}

/// Help window: topics on the left, the selected page on the right.
struct HelpView: View {
    @Environment(HelpNavigator.self) private var navigator

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: Binding(
                get: { navigator.topic },
                set: { if let topic = $0 { navigator.topic = topic } })) { topic in
                Label(topic.title, systemImage: topic.icon)
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            ScrollView {
                HelpPage(topic: navigator.topic)
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A new topic starts at the top.
            .id(navigator.topic)
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}

/// Opens the help window at a topic: as the standard round "?" button, or as a text button.
struct HelpButton: View {
    var topic: HelpTopic = .overview
    var title: String?
    @Environment(HelpNavigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let title {
            Button(title, systemImage: "questionmark.circle", action: open)
        } else {
            HelpLink(action: open)
                .help("Hilfe: \(topic.title)")
        }
    }

    private func open() {
        navigator.topic = topic
        openWindow(id: "help")
    }
}

struct HelpCommands: Commands {
    let navigator: HelpNavigator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Totalreflexion-Hilfe") { show(.overview) }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("Die drei Ansichten") { show(.views) }
            Button("Tastenkürzel & Maus") { show(.shortcuts) }
            Button("Probleme lösen") { show(.troubleshooting) }
        }
    }

    private func show(_ topic: HelpTopic) {
        navigator.topic = topic
        openWindow(id: "help")
    }
}

// MARK: - Building blocks for the pages

struct HelpHeader: View {
    let topic: HelpTopic
    let intro: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(topic.title, systemImage: topic.icon)
                .font(.largeTitle.weight(.semibold))
            HelpText(intro)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.top, 12)
            content()
        }
    }
}

/// Paragraph with **bold** markdown.
struct HelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LocalizedStringKey(text))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A feature or view with icon, explanation and an optional button that opens a window.
struct HelpCard: View {
    let icon: String
    let title: String
    let text: String
    var windowID: String?
    var buttonTitle = "Öffnen"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                HelpText(text)
                    .foregroundStyle(.secondary)
                if let windowID {
                    Button(buttonTitle) { openWindow(id: windowID) }
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HelpSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.tint, in: Circle())
                    HelpText(step)
                }
            }
        }
    }
}

/// Two-column table, e.g. key combination and what it does.
struct HelpTable: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    HelpText(row.1)
                }
            }
        }
    }
}

struct HelpTip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label {
            HelpText(text)
        } icon: {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Link to another help page.
struct HelpTopicLink: View {
    let topic: HelpTopic
    @Environment(HelpNavigator.self) private var navigator

    var body: some View {
        Button {
            navigator.topic = topic
        } label: {
            Label(topic.title, systemImage: "arrow.right.circle")
        }
        .buttonStyle(.link)
    }
}
