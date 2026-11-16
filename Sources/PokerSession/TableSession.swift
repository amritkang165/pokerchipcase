import Foundation
import Network
import Observation
import PokerCore
import PokerNet

/// A local operation that failed; `message` is the error's `localizedDescription`.
public struct SessionProblem: Equatable, Sendable {
    /// The kind of operation that failed.
    public enum Action: Sendable {
        /// Writing the host save file or the guest's seat ticket.
        case save
        /// Deleting the save file or seat ticket.
        case delete
        /// Sending a command to the host.
        case send
        /// Restarting the host listener.
        case listen
    }
    /// The operation that failed.
    public var action: Action
    /// `localizedDescription` of the underlying error.
    public var message: String
}

/// How the session's connection to the table is doing.
public enum ConnectionStatus: Equatable, Sendable {
    /// The first connection attempt is under way.
    case connecting
    /// The host has welcomed this device.
    case connected
    /// The connection dropped and the client is retrying.
    case reconnecting
    /// The client gave up for good; create a new session to try again.
    case failed(ClientFailure)
}

/// One device's seat at a table: the host device runs the `TableHost` and joins it over loopback,
/// a guest only has a `TableClient`. The app reads the state from here and sends commands through it.
/// After a host handover the session that carries on appears in `successor`.
@MainActor @Observable public final class TableSession {
    /// Name of the table, as shown in the lobby.
    public let tableName: String
    /// Code guests enter to connect.
    public let code: TableCode
    /// The latest game state; nil until the host has sent one.
    public private(set) var state: GameState?
    /// This device's player ID; nil until the host's `welcome` arrives.
    public private(set) var me: PlayerID?
    /// Connection health; `.connecting` until the first `welcome`.
    public private(set) var connection: ConnectionStatus = .connecting
    /// True while a command awaits its ack; further `send` calls are ignored then.
    public private(set) var isSending = false
    /// Number of `state` events handled; lets tests wait for one that changes nothing.
    private(set) var stateEvents = 0
    /// Reason of the last rejected command; cleared by `send` and by the next state newer than the one
    /// it was rejected on.
    public private(set) var rejection: Rejection?
    /// `state.version` the host had at or after it rejected the command behind `rejection`, or the last
    /// version this device knew when that command failed to send.
    private var rejectedAt = 0
    /// Last failed save, delete, send or listener restart; cleared when that action works again
    /// (`.send`: by the next `send` and by the next newer state, since a host that was suspended may still
    /// apply the command).
    public private(set) var problem: SessionProblem?

    /// The session that replaces this one after a host handover; nil otherwise. Switch to it as soon as it
    /// appears: this session is finished then.
    public private(set) var successor: TableSession?

    /// This device runs the `TableHost`.
    public var isHost: Bool { tableHost != nil }

    /// me's legal actions; nil when it is not my turn.
    public var legalActions: LegalActions? { me.flatMap { state?.legalActions(for: $0) } }

    /// Dealer of the hand or host: may resolve the showdown and start the next hand.
    public var canRunHand: Bool { isHost || (me != nil && me == state?.dealerID) }

    let client: TableClient
    private(set) var tableHost: TableHost?
    /// The host's listening port; nil on a guest.
    public private(set) var port: NWEndpoint.Port?
    private let name: String
    private let saveFile: SaveFile<HostSnapshot>?
    private let ticketFile: SaveFile<SeatTicket>?
    /// Started from the stored ticket's token, so a failure may delete that ticket.
    private let fromTicket: Bool
    /// Where a successor keeps its files after a host handover changes this device's role.
    private let handoverFiles: (host: SaveFile<HostSnapshot>, seat: SaveFile<SeatTicket>)
    /// The former host's save, on the guest session it stepped down to; deleted on the first `welcome`.
    private var retiredSave: SaveFile<HostSnapshot>?
    private var eventTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    private init(tableName: String, code: TableCode, name: String, client: TableClient, tableHost: TableHost?,
                 port: NWEndpoint.Port?, saveFile: SaveFile<HostSnapshot>?, ticketFile: SaveFile<SeatTicket>?,
                 handoverFiles: (host: SaveFile<HostSnapshot>, seat: SaveFile<SeatTicket>), fromTicket: Bool = false) {
        self.tableName = tableName
        self.code = code
        self.name = name
        self.client = client
        self.tableHost = tableHost
        self.port = port
        self.saveFile = saveFile
        self.ticketFile = ticketFile
        self.fromTicket = fromTicket
        self.handoverFiles = handoverFiles
    }

    /// Hosts `snapshot` (new or resumed) and joins it over loopback with the host token.
    /// `ticketFile` is used only if a host handover changes this device's role.
    public static func host(_ snapshot: HostSnapshot, saveFile: SaveFile<HostSnapshot> = .host,
                            ticketFile: SaveFile<SeatTicket> = .seat,
                            port: NWEndpoint.Port = .any) async throws -> TableSession {
        guard let token = snapshot.hostToken, let name = snapshot.game.state.seat(snapshot.game.state.hostID)?.name
        else { throw CocoaError(.fileReadCorruptFile) }
        // Saved before anything else, so a crash in the lobby is resumable too. Off the main actor: a long
        // tournament's file takes a noticeable fraction of a second to read and write.
        let previous = try await Task.detached {
            let old = saveFile.load()
            try saveFile.save(snapshot)
            return old
        }.value
        // Save results go to the session's `problem`; the host calls onChange on its own actor.
        let (saves, saved) = AsyncStream<(any Error)?>.makeStream()
        let host = TableHost(snapshot: snapshot, onChange: {
            do { try saveFile.save($0); saved.yield(nil) } catch { saved.yield(error) }
        })
        let bound: NWEndpoint.Port
        do { bound = try await host.start(port: port) } catch {
            // The table never opened: put the old save back (or remove the new one).
            if let previous { try? saveFile.save(previous) } else { try? saveFile.delete() }
            throw error
        }
        let client = TableClient(endpoint: .hostPort(host: "127.0.0.1", port: bound), code: snapshot.code,
                                 name: name, token: token)
        let session = TableSession(tableName: snapshot.tableName, code: snapshot.code, name: name, client: client,
                                   tableHost: host, port: bound, saveFile: saveFile, ticketFile: nil,
                                   handoverFiles: (saveFile, ticketFile))
        session.saveTask = Task { [weak session] in
            for await error in saves { session?.record(.save, error) }
        }
        await session.start()
        return session
    }

    /// Joins the table at `endpoint`; pass the `token` of a saved ticket to reclaim a seat. Returns at once, `connection` reports progress.
    /// `saveFile` is used only if a host handover changes this device's role.
    public static func join(endpoint: NWEndpoint, tableName: String, code: TableCode, name: String,
                            token: String? = nil, ticketFile: SaveFile<SeatTicket> = .seat,
                            saveFile: SaveFile<HostSnapshot> = .host) async -> TableSession {
        let client = TableClient(endpoint: endpoint, code: code, name: name, token: token)
        let session = TableSession(tableName: tableName, code: code, name: name, client: client,
                                   tableHost: nil, port: nil, saveFile: nil, ticketFile: ticketFile,
                                   handoverFiles: (saveFile, ticketFile), fromTicket: token != nil)
        await session.start()
        return session
    }

    /// Sends a command and waits for the ack; a refusal lands in `rejection`, other failures in `problem`.
    public func send(_ command: Command) async {
        guard !isSending else { return }  // double tap
        isSending = true
        rejection = nil
        record(.send, nil)
        defer { isSending = false }
        do {
            if case let .rejected(reason) = try await client.send(command) {
                // The host sends every state before its ack, so lastState is the state it rejected on.
                // ponytail: a state arriving between the ack and this read counts as old, so the banner
                // outlives one real change; return the version from TableClient.send if that shows.
                rejectedAt = await client.lastState?.version ?? 0
                rejection = reason
            }
        } catch {
            rejectedAt = await client.lastState?.version ?? 0
            record(.send, error)
        }
    }

    /// Plays `action` for this device's own player; does nothing before `me` is known.
    public func act(_ action: Action) async {
        guard let me else { return }
        await send(.act(player: me, action: action))
    }

    /// Call when the scene becomes active: restarts the host listener iOS tore down.
    public func appBecameActive() async {
        // ponytail: if the old port is taken the table stays unreachable; restart on .any + new loopback client if that happens in practice
        do {
            try await tableHost?.ensureListening()
            record(.listen, nil)
        } catch {
            record(.listen, error)
        }
    }

    /// Disconnects; a guest in the lobby gives up their seat first, the host also ends the table for everyone.
    /// Deletes this device's save file and seat ticket (the ticket stays after `removed`, for an undo by the host)
    /// and returns false if that failed (`problem` says why; calling `leave()` again retries).
    @discardableResult public func leave() async -> Bool {
        eventTask?.cancel()
        eventTask = nil  // a queued stepDown must not create a successor after the user left
        saveTask?.cancel()
        if !isHost, state?.phase == .lobby, let me {
            // A silent host must not hold the leave back for the whole ackTimeout: disconnecting fails the send.
            let giveUp = Task { [client] in
                try await Task.sleep(for: .seconds(2))
                await client.disconnect()
            }
            // ponytail: one attempt. A change racing the leave rejects it as staleState and the seat stays
            // until the host removes it; retry once on that rejection if it shows.
            _ = try? await client.send(.removePlayer(player: me))
            giveUp.cancel()
        }
        await client.disconnect()
        await tableHost?.end()
        let keepTicket = connection == .failed(.removed)
        return record(.delete) {
            try saveFile?.delete()
            if !keepTicket { try ticketFile?.delete() }
        }
    }

    /// Sets `problem` for a failed `action`, or clears it when that action worked.
    private func record(_ action: SessionProblem.Action, _ error: (any Error)?) {
        if let error {
            problem = SessionProblem(action: action, message: error.localizedDescription)
        } else if problem?.action == action {
            problem = nil
        }
    }

    @discardableResult private func record(_ action: SessionProblem.Action, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            record(action, nil)
            return true
        } catch {
            record(action, error)
            return false
        }
    }

    private func start() async {
        eventTask = Task { [weak self, events = client.events] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
        await client.connect()
    }

    private func handle(_ event: ClientEvent) {
        switch event {
        case let .welcome(welcome):
            me = welcome.player
            connection = .connected
            let ticketSaved = record(.save) {
                try ticketFile?.save(SeatTicket(tableName: tableName, code: code, name: name, token: welcome.token))
            }
            // Without the ticket the host save is the only way back to this table, so it stays.
            if ticketSaved, let retired = retiredSave {
                retiredSave = nil
                record(.delete) { try retired.delete() }
            }
        case let .state(new):
            state = new
            stateEvents += 1
            if new.version > rejectedAt {
                rejection = nil
                if problem?.action == .send { problem = nil }
            }
        case let .handover(handover):
            Task { await takeOver(handover) }
        case .connectionLost:
            connection = .reconnecting
            if let tableHost {
                Task { if await tableHost.handedOver { await stepDown() } }
            }
        case let .failed(failure):
            connection = .failed(failure)
            // Only our own ticket: one we rejoined with or saved on welcome, never another table's.
            // After `removed` the ticket stays: an undo by the host gives the seat back to it.
            if fromTicket || me != nil, failure != .removed { record(.delete) { try ticketFile?.delete() } }
        }
    }

    /// A guest becomes the host: starts the table from the handover and publishes the host session.
    private func takeOver(_ handover: Handover) async {
        guard successor == nil, !isHost else { return }
        await client.disconnect()
        let snapshot = HostSnapshot(game: handover.game, tokens: handover.tokens, tableName: tableName, code: code)
        do {
            let next = try await TableSession.host(snapshot, saveFile: handoverFiles.host, ticketFile: handoverFiles.seat)
            eventTask?.cancel()
            record(.delete) { try ticketFile?.delete() }
            next.adopt(self)
            successor = next
        } catch {
            record(.listen, error)
            // Disconnected by hand above, so the client reports no connectionLost.
            connection = .reconnecting
            await client.connect()
        }
    }

    /// The former host becomes a guest: publishes a session that reconnects by the table's Bonjour name.
    private func stepDown() async {
        // Every connectionLost after the handover lands here; clearing eventTask before the first await
        // lets only the first one through.
        guard successor == nil, let events = eventTask else { return }
        events.cancel()
        eventTask = nil
        saveTask?.cancel()
        let token = await client.token
        await client.disconnect()
        let endpoint = NWEndpoint.service(name: tableName, type: Wire.serviceType, domain: "local.", interface: nil)
        let next = TableSession(tableName: tableName, code: code, name: name,
                                client: TableClient(endpoint: endpoint, code: code, name: name, token: token),
                                tableHost: nil, port: nil, saveFile: nil, ticketFile: handoverFiles.seat,
                                handoverFiles: handoverFiles, fromTicket: true)
        next.adopt(self)
        next.connection = .reconnecting
        // The save stays until the new host answers: if it never does, the player resumes from it.
        next.retiredSave = handoverFiles.host
        await next.start()
        successor = next
    }

    /// Shows the predecessor's table until this session's own first state arrives.
    private func adopt(_ old: TableSession) {
        guard state == nil else { return }
        state = old.state
        me = old.me
    }
}
