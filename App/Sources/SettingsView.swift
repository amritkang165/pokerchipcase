import PokerCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var themeName = ThemeName.felt
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("cardBack") private var cardBack = CardBack.red
    @AppStorage("cardBackPattern") private var cardBackPattern = CardBackPattern.medallion
    @AppStorage("cardFace") private var cardFace = CardFace.classic
    @AppStorage("fourColorDeck") private var fourColorDeck = false
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
                    // Reads the stored choices, so it follows every row below.
                    HStack(spacing: 12) {
                        ForEach(["As", "Td"].compactMap(Card.init), id: \.self) { CardFaceView(card: $0, width: 44) }
                        CardBackView(back: cardBack, width: 44)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityHidden(true)
                    Picker("Card face", selection: $cardFace) {
                        ForEach(CardFace.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Four-color deck", isOn: $fourColorDeck)
                    Picker("Back pattern", selection: $cardBackPattern) {
                        ForEach(CardBackPattern.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Cards").foregroundStyle(theme.muted)
                }
                .themedRow()

                Section {
                    Picker("Back color", selection: $cardBack) {
                        ForEach(CardBack.allCases, id: \.self) { back in
                            Label { Text(back.label) } icon: { CardBackView(back: back, width: 22) }.tag(back)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Back color").foregroundStyle(theme.muted)
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
