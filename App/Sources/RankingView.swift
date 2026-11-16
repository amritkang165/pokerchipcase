import PokerCore
import PokerSession
import SwiftUI

struct RankingView: View {
    let state: GameState
    let onLeave: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Text("Final ranking").font(.title.bold())
            List {
                ForEach(Array(state.ranking.enumerated()), id: \.element.id) { i, seat in
                    HStack {
                        Text("\(i + 1). \(seat.name)")
                        if i == 0 {
                            Spacer()
                            Text("\(seat.stack)").monospacedDigit().bold()
                        }
                    }
                    .themedRow()
                }
                // The last payout ends the game before the table can show it.
                let revealed = state.config.digitalCards ? state.seats.filter(state.isRevealed) : []
                if !revealed.isEmpty {
                    Section("Final hand") {
                        HStack(spacing: 4) {
                            ForEach(state.board, id: \.self) { CardFaceView(card: $0, width: 34) }
                        }
                        .themedRow()
                        ForEach(revealed, id: \.id) { seat in
                            HStack {
                                Text(seat.name)
                                CardsText(cards: seat.holeCards)
                                if let value = state.handValue(of: seat) {
                                    Spacer()
                                    Text(value.name).foregroundStyle(theme.muted)
                                }
                            }
                            .themedRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            Button("Leave table", action: onLeave)
            .buttonStyle(ThemeButtonStyle())
            .padding(.bottom)
        }
        .padding(.horizontal)
    }
}
