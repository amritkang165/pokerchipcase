import Foundation
import Network
import PokerCore

/// Server for one table: owns the snapshot, accepts connections, applies commands and broadcasts state.
///
/// iOS tears down listening sockets while an app is suspended. Call `ensureListening()` whenever the
/// app becomes active again; it restarts the listener on the same port if it has stopped.
///
/// An accepted `transferHost` hands the table over: the target gets a `handover` and the host stops serving.
public actor TableHost {
    /// The current game, tokens and table identity; changes with every accepted command and every new player's hello.
    public private(set) var snapshot: HostSnapshot
    private let onChange: @Sendable (HostSnapshot) -> Void
    private let queue = DispatchQueue(label: "pokernet.host")
    private var listener: NWListener?
    /// Identifies `listener` in its callbacks. Not ObjectIdentifier: a new listener can reuse the old one's address.
    private var listenerID = 0
    /// Finishes once `listener` is cancelled and has let go of its port.
    private var listenerGone: AsyncStream<Never>?
    /// Port of the last successful start; nil after `stop()`.
    private var port: NWEndpoint.Port?
    /// The most recent `start`; the next one waits for it.
    private var lastStart: Task<NWEndpoint.Port, Error>?
    /// Counts `stop()` calls; a start that began before the latest stop gives up instead of binding.
    private var stops = 0
    /// Tests only: awaited at the start of every bind, to hold a start while the test calls `stop()`.
    var beforeBind: (@Sendable () async -> Void)?
    private var channels: [UUID: MessageChannel] = [:]
    private var bound: [UUID: PlayerID] = [:]
    private let helloTimeout: Duration
    private let liveWindow: Duration
    /// When each connection last sent a message.
    private var lastHeard: [UUID: ContinuousClock.Instant] = [:]

    /// True once this host accepted a `transferHost`: it has stopped serving and another device hosts the table.
    public private(set) var handedOver = false

    /// Undo steps a handover carries; the whole history of a long tournament exceeds `MessageChannel.maxMessageSize`.
    static let handoverHistory = 50

    /// Longest seat name, in characters; the host cuts longer names, which bloat every state message.
    public static let maxNameLength = 32
    /// Byte limit for the same name: one character can hold any number of combining marks.
    static let maxNameBytes = 256

    /// The name a guest is seated with: trimmed, at most ``maxNameLength`` whole characters and ``maxNameBytes``
    /// bytes, "Player" if nothing is left.
    static func seatName(_ raw: String) -> String {
        var name = ""
        for c in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard name.count < maxNameLength, name.utf8.count + c.utf8.count <= maxNameBytes else { break }
            name.append(c)
        }
        return name.isEmpty ? "Player" : name
    }

    /// `onChange` receives every new snapshot; persist it to resume after a crash.
    /// `helloTimeout`: a connection that has not finished TLS and `hello` by then is closed.
    /// `liveWindow`: a handover target must have sent a message within this time.
    public init(snapshot: HostSnapshot, helloTimeout: Duration = .seconds(10), liveWindow: Duration = .seconds(12),
                onChange: @escaping @Sendable (HostSnapshot) -> Void = { _ in /* no observer by default */ }) {
        self.snapshot = snapshot
        self.helloTimeout = helloTimeout
        self.liveWindow = liveWindow
        self.onChange = onChange
    }

    /// Players with a live connection that has finished `hello`.
    public var connectedPlayers: Set<PlayerID> { Set(bound.values) }

    /// True while the listener accepts connections.
    public var isListening: Bool { listener?.state == .ready }

    /// Starts listening (stopping a previous listener first) and returns the bound port.
    /// Concurrent calls run one after another in call order. Cancelling a caller does not cancel its bind;
    /// a `stop()` does, and the start throws `CancellationError`.
    public func start(port: NWEndpoint.Port = .any) async throws -> NWEndpoint.Port {
        let stops = stops
        // Each start waits for the previous one, so two restarts cannot race for the port (#71).
        let task = Task { [lastStart] in
            _ = await lastStart?.result
            return try await bind(port: port, stops: stops)
        }
        lastStart = task
        return try await task.value
    }

    private func bind(port: NWEndpoint.Port, stops: Int) async throws -> NWEndpoint.Port {
        await beforeBind?()
        await cancelListener()
        // A table that was stopped while this start waited must not listen and advertise again (#107).
        guard stops == self.stops else { throw CancellationError() }
        // A start suspended before the handover must not open a listener with the same Bonjour name.
        guard !handedOver else { throw NWError.posix(.ECANCELED) }
        let listener = try NWListener(using: PSK.parameters(code: snapshot.code), on: port)
        listener.service = NWListener.Service(name: snapshot.tableName, type: Wire.serviceType)
        listenerID += 1
        let id = listenerID
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection, from: id) }
        }
        let (gone, isGone) = AsyncStream<Never>.makeStream()
        // Started before it is stored, so a concurrent `start` that cancels it always gets the callback.
        let ready = listener.startReporting(queue: queue) { [weak self] in
            isGone.finish()
            Task { await self?.listenerStopped(id) }
        }
        self.listener = listener
        listenerGone = gone
        do {
            for try await bound in ready {
                self.port = bound
                return bound
            }
            throw NWError.posix(.ECANCELED)
        } catch {
            listenerStopped(id)
            throw error
        }
    }

    /// Restarts the listener on its previous port if it has stopped (e.g. after the app was suspended).
    /// Checks the listener's own state: the `listenerStopped` callback can land after the app is active again (#46).
    public func ensureListening() async throws {
        guard let port else { return }
        switch listener?.state {
        case .setup?, .ready?: return
        default: _ = try await start(port: port)
        }
    }

    /// Ends the table: every connection gets a final `tableClosed`, then the host stops listening.
    public func end() {
        for id in channels.keys { reject(.tableClosed, id, replyTo: nil) }
        stop()
    }

    /// Stops without telling anyone, like a host that vanished; clients keep reconnecting.
    public func stop() {
        stops += 1
        port = nil
        listener?.cancel()
        listener = nil
        listenerGone = nil
        disconnectAll()
    }

    func disconnectAll(graceful: Bool = false) {
        for channel in channels.values { if graceful { channel.close() } else { channel.cancel() } }
        channels = [:]
        bound = [:]
        lastHeard = [:]
    }

    /// `callbackLost`: the listener stops, but `listenerStopped` ignores it, like a callback that lands late.
    func simulateListenerFailure(callbackLost: Bool = false) {
        if callbackLost { listenerID += 1 }
        listener?.cancel()
    }

    /// Cancels the listener and waits until it is gone, so a new one can bind the same port.
    private func cancelListener() async {
        guard let old = listener else { return }
        let gone = listenerGone
        listener = nil
        listenerGone = nil
        old.cancel()
        if let gone {
            for await _ in gone {
                // Only waits for the stream to end.
            }
        }
    }

    private func listenerStopped(_ id: Int) {
        guard id == listenerID else { return }
        listener = nil
        listenerGone = nil
    }

    /// Only the current listener's connections; a late one from a replaced listener is turned away.
    private func accept(_ connection: NWConnection, from id: Int) {
        guard listener != nil, id == listenerID else { return connection.cancel() }
        let id = UUID()
        let channel = MessageChannel(connection: connection)
        channels[id] = channel
        Task { [weak self] in
            do {
                for try await event in channel.events {
                    if case let .message(data) = event { await self?.receive(data, from: id) }
                }
            } catch {
                // A failed channel ends like a closed one: dropped below.
            }
            await self?.drop(id)
        }
        Task { [weak self, helloTimeout] in
            try? await Task.sleep(for: helloTimeout)
            await self?.dropIfUnbound(id)
        }
        channel.start()
    }

    private func dropIfUnbound(_ id: UUID) {
        guard bound[id] == nil, let channel = channels[id] else { return }
        channel.cancel()
        drop(id)
    }

    private func drop(_ id: UUID) {
        channels[id] = nil
        bound[id] = nil
        lastHeard[id] = nil
    }

    private func receive(_ data: Data, from id: UUID) {
        guard !handedOver, channels[id] != nil else { return }
        lastHeard[id] = .now
        // Errors reuse the request's envelope id so the sender can match them to its command.
        let messageID: UUID
        let message: ClientMessage
        do {
            (messageID, message) = try Wire.decodeClient(data)
        } catch WireError.versionMismatch {
            return reject(.versionMismatch, id, replyTo: Wire.envelopeID(data))
        } catch {
            return send(.error(WireErrorCode.malformed.rawValue), to: id, envelopeID: Wire.envelopeID(data))
        }
        switch message {
        case let .hello(hello):
            welcome(hello, from: id, requestID: messageID)
        case let .command(request):
            handle(request, messageID: messageID, from: id)
        case .ping:
            send(.pong, to: id, envelopeID: messageID)
        }
    }

    private func handle(_ request: CommandRequest, messageID: UUID, from id: UUID) {
        guard let player = bound[id] else {
            return send(.error(WireErrorCode.helloRequired.rawValue), to: id, envelopeID: messageID)
        }
        var target: UUID?
        if case let .transferHost(to: heir) = request.command {
            // A suspended app keeps its connection but sends nothing, so a bound connection is not enough.
            let now = ContinuousClock.now
            target = bound.first { $0.value == heir && lastHeard[$0.key].map { now - $0 < liveWindow } == true }?.key
            if target == nil {
                return send(.ack(Ack(id: messageID, result: .rejected(reason: .playerOffline))), to: id)
            }
        }
        do {
            try snapshot.game.apply(request.command, by: player, at: Date(), expectedVersion: request.stateVersion)
        } catch {
            return send(.ack(Ack(id: messageID, result: .rejected(reason: error))), to: id)
        }
        if let target {
            // No onChange: the save keeps this device as host, so it can resume if the target fails.
            broadcastState()
            send(.ack(Ack(id: messageID, result: .ok)), to: id)
            handedOver = true
            port = nil
            Task { await finishHandover(to: target) }
            return
        }
        if case let .removePlayer(removed) = request.command { kick(removed) }
        kickUnseatedPlayers()
        onChange(snapshot)
        // State before ack: when a client's send returns, it already knows the new state version.
        broadcastState()
        send(.ack(Ack(id: messageID, result: .ok)), to: id)
    }

    /// Frees the Bonjour name first so the target can register it, then sends the handover and closes everything.
    private func finishHandover(to id: UUID) async {
        await cancelListener()
        var game = snapshot.game
        game.keepHistory(last: Self.handoverHistory)
        if let data = try? Wire.encode(ServerMessage.handover(Handover(game: game, tokens: snapshot.tokens)), id: UUID()) {
            channels[id]?.sendAndClose(data)
        }
        drop(id)
        disconnectAll(graceful: true)
    }

    /// A player removed mid-game keeps the seat (folded, out) and the token, so an undo can give the seat back;
    /// the connection closes.
    private func kick(_ player: PlayerID) {
        for (id, p) in bound where p == player { reject(.removed, id, replyTo: nil) }
    }

    /// Players without a seat (removed in the lobby, or their join was undone) lose their connection.
    /// Their token stays: in the lobby, `welcome` seats them again under the old ID.
    // ponytail: tokens are never pruned; each tokenless join adds about 80 bytes
    // to every save and handover. Prune tokens whose player is neither seated nor in Game.history if saves grow
    // noticeably (#128).
    private func kickUnseatedPlayers() {
        let seated = Set(snapshot.game.state.seats.map(\.id))
        for (id, player) in bound where !seated.contains(player) {
            reject(.removed, id, replyTo: nil)
        }
    }

    private func welcome(_ hello: Hello, from id: UUID, requestID: UUID?) {
        guard bound[id] == nil else {
            return send(.error(WireErrorCode.malformed.rawValue), to: id, envelopeID: requestID)
        }
        let player: PlayerID
        let token: String
        if let t = hello.token, let p = snapshot.tokens[t], snapshot.game.state.seat(p) != nil {
            player = p
            token = t
            // The newest connection for a player wins. Usually the old one is dead; if it is another
            // device sharing the token, `replaced` stops it from taking the seat back.
            for (other, q) in bound where q == p && other != id { reject(.replaced, other, replyTo: nil) }
        } else {
            // A removed player rejoins under the old ID and token, so undoing the removal finds them again (#126).
            let known = hello.token.flatMap { snapshot.tokens[$0] }
            player = known ?? UUID().uuidString
            do {
                try snapshot.game.apply(.join(player: player, name: Self.seatName(hello.name)), by: snapshot.game.state.hostID, at: Date())
            } catch .tableFull {
                return reject(.tableFull, id, replyTo: requestID)
            } catch {
                return reject(.gameInProgress, id, replyTo: requestID)
            }
            if known != nil, let t = hello.token {
                token = t
            } else {
                token = UUID().uuidString
                snapshot.tokens[token] = player
            }
            onChange(snapshot)
        }
        bound[id] = player
        send(.welcome(Welcome(player: player, token: token)), to: id)
        broadcastState()
    }

    /// Sends a final error and closes the connection.
    private func reject(_ code: WireErrorCode, _ id: UUID, replyTo requestID: UUID?) {
        guard let data = try? Wire.encode(ServerMessage.error(code.rawValue), id: requestID ?? UUID()) else { return }
        channels[id]?.sendAndClose(data)
        drop(id)
    }

    private func send(_ message: ServerMessage, to id: UUID, envelopeID: UUID? = nil) {
        guard let data = try? Wire.encode(message, id: envelopeID ?? UUID()) else { return }
        channels[id]?.send(data)
    }

    private func broadcastState() {
        for (id, player) in bound { send(.state(snapshot.game.state.redacted(for: player)), to: id) }
    }
}

extension NWListener {
    /// Starts the listener. The stream yields the port once ready and finishes, or throws if the listener
    /// fails first. `onCancelled` fires once the listener is cancelled; a failed one cancels itself.
    func startReporting(
        queue: DispatchQueue, onCancelled: @escaping @Sendable () -> Void = { /* no observer by default */ }
    ) -> AsyncThrowingStream<NWEndpoint.Port, Error> {
        let (ready, continuation) = AsyncThrowingStream<NWEndpoint.Port, Error>.makeStream()
        stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.port { continuation.yield(port) }
                continuation.finish()
            case let .waiting(error), let .failed(error):
                // Waiting: e.g. the port is taken; treat as failure instead of hanging.
                continuation.finish(throwing: error)
                self?.cancel()
            case .cancelled:
                continuation.finish()
                onCancelled()
            default:
                break
            }
        }
        start(queue: queue)
        return ready
    }

    /// Starts the listener and waits until it is ready.
    func startAndWaitUntilReady(queue: DispatchQueue) async throws -> NWEndpoint.Port {
        for try await port in startReporting(queue: queue) { return port }
        throw NWError.posix(.ECANCELED)
    }
}
