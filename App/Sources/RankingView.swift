import PokerCore
import PokerSession
import SwiftUI

struct RankingView: View {
    let state: GameState
    let onLeave: () -> Void
    @Environment(\.theme) private var theme

    /// Seats whose cards were shown in the last hand; the last payout ends the game before the table can show it.
    private var revealed: [Seat] { state.config.digitalCards ? state.seats.filter(state.isRevealed) : [] }

    var body: some View {
        VStack(spacing: 12) {
            Text("Final ranking").font(.title.bold())
            ScrollView {
                VStack(spacing: 12) {
                    ranking
                    if !revealed.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(state.board, id: \.self) { CardFaceView(card: $0, width: 44) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Board: " + state.board.spokenNames)
                    }
                }
            }
            Button("Leave table", action: onLeave)
                .buttonStyle(ThemeButtonStyle())
                .padding(.bottom)
        }
        .padding(.horizontal)
    }

    /// One row per player in ranking order; with digital cards also the cards and hand each player showed in the last hand.
    private var ranking: some View {
        let cards = !revealed.isEmpty
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Name")
                if cards {
                    Text("Cards")
                    Text("Hand")
                }
                Text("Chips").gridColumnAlignment(.trailing)
            }
            .font(.caption).foregroundStyle(theme.muted)
            ForEach(Array(state.ranking.enumerated()), id: \.element.id) { i, seat in
                Divider()
                GridRow {
                    Text("\(i + 1). \(seat.name)").fontWeight(i == 0 ? .bold : .regular)
                    if cards {
                        let shown = revealed.contains { $0.id == seat.id }
                        if shown { CardsText(cards: seat.holeCards) } else { Text("") }
                        Text(shown ? state.handValue(of: seat)?.name ?? "" : "").foregroundStyle(theme.muted)
                    }
                    // Only the winner holds chips at the end.
                    Text(seat.stack > 0 ? "\(seat.stack)" : "").monospacedDigit().bold()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(12)
        .background(theme.seat, in: .rect(cornerRadius: 10))
    }
}
