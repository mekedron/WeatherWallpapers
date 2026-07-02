import SwiftUI
import AppIntents

/// Step-by-step instructions for wiring the app into Shortcuts automations.
struct ShortcutsGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    section(
                        title: "guide.shortcut.title",
                        steps: [
                            "guide.shortcut.step1",
                            "guide.shortcut.step2",
                            "guide.shortcut.step3",
                            "guide.shortcut.step4",
                        ]
                    )
                    section(
                        title: "guide.automation.title",
                        steps: [
                            "guide.automation.step1",
                            "guide.automation.step2",
                            "guide.automation.step3",
                        ]
                    )
                    macSection
                    footerNote
                }
                .padding()
            }
            .navigationTitle("Shortcuts Guide")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("guide.intro.title")
                    .font(.title2.bold())
            } icon: {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.tint)
            }
            Text("guide.intro.body")
                .foregroundStyle(.secondary)
            #if os(iOS)
            ShortcutsLink()
            #endif
        }
    }

    private func section(title: LocalizedStringKey, steps: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                    Text(step)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var macSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("guide.mac.title")
                .font(.headline)
            Text("guide.mac.body")
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: macScript)
                .font(.caption.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var macScript: String {
        """
        tell application "System Events"
            set picture of every desktop to (POSIX path of input)
        end tell
        """
    }

    private var footerNote: some View {
        Label {
            Text("guide.note")
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.tint)
        }
    }
}
