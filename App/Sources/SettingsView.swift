import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var themeName = ThemeName.felt
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("cardBack") private var cardBack = CardBack.red
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $themeName) {
                        ForEach(ThemeName.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Brightness", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .themedRow()

                Section {
                    Picker("Card back", selection: $cardBack) {
                        ForEach(CardBack.allCases, id: \.self) { back in
                            Label { Text(back.label) } icon: { CardBackView(back: back, width: 22) }.tag(back)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Card back").foregroundStyle(theme.muted)
                }
                .themedRow()
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .themedScreen()
        }
    }
}
