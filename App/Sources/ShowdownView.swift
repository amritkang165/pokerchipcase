import PokerCore
import PokerSession
import SwiftUI

private func dealerName(_ state: GameState) -> String {
    state.dealerID.flatMap { state.seat($0)?.name } ?? ""
}

/// The pot picker and "Pay out" for the player running the hand. The winners are picked on the
/// table (`TableView` owns the selection); everyone else waits.
struct ShowdownView: View {
    let session: TableSession
    let state: GameState
    @Binding var winners: [Set<PlayerID>]
    @Binding var pot: Int
    @Environment(\.theme) private var theme

    private var ready: Bool { winners.count == state.pots.count && !winners.contains { $0.isEmpty } }

    var body: some View {
        if session.canRunHand {
            VStack(spacing: 8) {
                if state.pots.count > 1 {
                    Picker("Pot", selection: $pot) {
                        ForEach(state.pots.indices, id: \.self) { i in
                            Text("\(potName(i, of: state.pots.count)) \(state.pots[i].amount)").tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Text("Tap the winners on the table").font(.caption).foregroundStyle(theme.muted)
                Button("Pay out") { payOut() }
                    .buttonStyle(ThemeButtonStyle())
                    .disabled(session.isSending || !ready)
            }
            .padding(.bottom)
        } else {
            Text("Waiting for \(dealerName(state)) to pick the winners").foregroundStyle(theme.muted).padding(.bottom)
        }
    }

    private func payOut() {
        let order = state.seats.map(\.id)
        let lists = winners.map { chosen in order.filter(chosen.contains) }
        Task { await session.send(.resolveShowdown(winners: lists)) }
    }
}

struct NextHandBar: View {
    let session: TableSession
    let state: GameState
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if session.canRunHand {
                Button("Next hand") { Task { await session.send(.startNextHand) } }
                    .buttonStyle(ThemeButtonStyle())
                    .disabled(session.isSending)
            } else {
                Text("Waiting for \(dealerName(state)) to start the next hand").foregroundStyle(theme.muted)
            }
        }
        .padding(.bottom)
    }
}
