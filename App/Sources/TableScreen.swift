import PokerCore
import PokerNet
import PokerSession
import SwiftUI

struct TableScreen: View {
    let session: TableSession
    let nearby: NearbyTables
    let onLeave: () -> Void
    @State private var confirmLeave = false
    @State private var hostPending: HostConfirm?
    @State private var leaveFailed = false
    @State private var showSettings = false
    /// A send still running after a moment; a fast one shows no banner, which would push the screen down and back.
    @State private var slowSend = false
    @Environment(\.theme) private var theme

    init(session: TableSession, nearby: NearbyTables, onLeave: @escaping () -> Void) {
        self.session = session
        self.nearby = nearby
        self.onLeave = onLeave
    }

    private var failure: Binding<Bool> {
        // Not again after its OK when a failed delete kept the screen open.
        Binding(get: { if case .failed = session.connection { !leaveFailed } else { false } }, set: { _ in
            // Read-only: the connection state decides, not the alert.
        })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let state = session.state {
                    if state.phase == .lobby {
                        LobbyView(session: session, state: state, nearby: nearby)
                    } else if state.phase == .finished {
                        RankingView(state: state, onLeave: leave)
                    } else {
                        TableView(session: session, state: state)
                            // iOS 18 keeps the bar's background and hairline once the banner has
                            // been shown; the table does not scroll, so it never needs them.
                            .toolbarBackground(.hidden, for: .navigationBar)
                    }
                } else {
                    ProgressView("Connecting…").foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(session.tableName)
            // Inline, so the table gets the height on small iPhones.
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { banner }
            .task(id: session.isSending) {
                slowSend = false
                guard session.isSending, (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
                slowSend = true
            }
            // Here, not in ActionBar: that is re-inserted every hand with the trigger already set.
            // nil while waiting, the street on my turn, so a new street during my turn fires too.
            .sensoryFeedback(.warning, trigger: session.legalActions != nil ? session.state?.street : nil) { $1 != nil }
            .toolbar {
                Menu("Table", systemImage: "ellipsis.circle") {
                    if session.isHost, let state = session.state, state.phase != .lobby {
                        HostMenu(session: session, state: state, pending: $hostPending)
                            .disabled(session.isSending)
                        Divider()
                    }
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                    Divider()
                    Button(session.isHost ? "End table" : "Leave table", role: .destructive) { confirmLeave = true }
                }
            }
            // Before the dialogs, so they keep the root's formTint like StartView's.
            .themedScreen()
            .hostConfirmation($hostPending, session: session)
            .onChange(of: session.state?.version) { hostPending = nil }
            .confirmationDialog(
                session.isHost ? "End the table for everyone?" : "Leave the table? You can't rejoin once the tournament has started.",
                isPresented: $confirmLeave, titleVisibility: .visible
            ) {
                Button(session.isHost ? "End table" : "Leave table", role: .destructive) { leave() }
            }
            .alert(failureMessage, isPresented: failure) { Button("OK") { leave() } }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var failureMessage: String {
        if case let .failed(f) = session.connection { f.message } else { "" }
    }

    /// Nothing at all when there is no message, so no empty bar shows above the table.
    /// On the seat fill: the room is too light for red text in the light palettes.
    @ViewBuilder private var banner: some View {
        if let text = bannerText {
            text.foregroundStyle(theme.seatText).frame(maxWidth: .infinity).padding(6).background(theme.seat)
        }
    }

    private var bannerText: Text? {
        if session.connection == .reconnecting { return Text("Reconnecting…") }
        if session.isSending, slowSend { return Text("Sending…") }
        if let rejection = session.rejection { return Text(rejection.message).foregroundStyle(theme.red) }
        if let problem = session.problem { return Text(problem.text).foregroundStyle(theme.red) }
        return nil
    }

    private func leave() {
        Task {
            // A failed delete keeps the table open with the banner; leaving again retries.
            if await session.leave() { onLeave() } else { leaveFailed = true }
        }
    }
}
