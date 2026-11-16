import Foundation
import Network
import Testing
@testable import PokerCore
@testable import PokerNet
@testable import PokerSession

@MainActor @Suite(.timeLimit(.minutes(2)))
struct HandoverTests {
    /// A name of its own for every test: the old host's guest session looks the table up by name over
    /// Bonjour, and the other suites host tables called "Test" at the same time.
    private func uniqueName() -> String { "T-\(UUID().uuidString.prefix(8))" }

    private func hostUnique(_ save: SaveFile<HostSnapshot> = tempFile()) async throws -> TableSession {
        let anna = try await TableSession.host(
            .newTable(hostName: "Anna", tableName: uniqueName(), code: code4711, config: .relaxed),
            saveFile: save, ticketFile: tempFile())
        try await eventually { anna.state != nil }
        return anna
    }

    /// Over Bonjour, like on real devices: the guests find the new host by the table name.
    @Test func handoverMovesTheTableToAGuest() async throws {
        let name = uniqueName()
        let annaSave: SaveFile<HostSnapshot> = tempFile()
        let benSave: SaveFile<HostSnapshot> = tempFile()
        let annaTicket: SaveFile<SeatTicket> = tempFile()
        let benTicket: SaveFile<SeatTicket> = tempFile()
        let service = NWEndpoint.service(name: name, type: Wire.serviceType, domain: "local.", interface: nil)
        let anna = try await TableSession.host(
            .newTable(hostName: "Anna", tableName: name, code: code4711, config: .relaxed),
            saveFile: annaSave, ticketFile: annaTicket)
        let ben = await TableSession.join(endpoint: service, tableName: name, code: code4711, name: "Ben",
                                          ticketFile: benTicket, saveFile: benSave)
        let cem = await TableSession.join(endpoint: service, tableName: name, code: code4711, name: "Cem",
                                          ticketFile: tempFile(), saveFile: tempFile())
        defer { Task { await cem.leave() } }
        try await eventually(timeout: .seconds(30)) {
            anna.state?.seats.count == 3 && ben.me != nil && cem.me != nil && benTicket.load() != nil
        }
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { [anna, ben, cem].allSatisfy { $0.state?.phase == .betting } }

        await anna.send(.transferHost(to: ben.me!))
        try await eventually(timeout: .seconds(30)) { anna.successor != nil && ben.successor != nil }
        let newHost = ben.successor!
        let oldHost = anna.successor!
        defer { Task { await oldHost.leave(); await newHost.leave() } }
        try await eventually(timeout: .seconds(30)) {
            await newHost.tableHost!.connectedPlayers == [anna.me!, ben.me!, cem.me!]
                && oldHost.connection == .connected && cem.connection == .connected && cem.state?.hostID == ben.me
        }
        #expect(newHost.isHost && newHost.me == ben.me && newHost.tableName == name)
        #expect(!oldHost.isHost && oldHost.me == anna.me)
        #expect(benSave.load()?.game.state.hostID == ben.me && benTicket.load() == nil)
        try await eventually { annaSave.load() == nil }
        #expect(annaTicket.load()?.tableName == name)

        await newHost.send(.pauseClock)
        #expect(newHost.rejection == nil)
        try await eventually { oldHost.state?.clock.isPaused == true }
        await oldHost.send(.resumeClock)
        #expect(oldHost.rejection == .notHost)
    }

    /// The target is a plain client that never hosts, like a crashed app.
    @Test func oldHostKeepsItsSaveUntilTheNewHostAnswers() async throws {
        let save: SaveFile<HostSnapshot> = tempFile()
        let anna = try await hostUnique(save)
        let ben = TableClient(endpoint: .hostPort(host: "127.0.0.1", port: anna.port!), code: code4711, name: "Ben")
        await ben.connect()
        try await eventually { anna.state?.seats.count == 2 }
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { anna.state?.phase == .betting }
        let target = anna.state!.seats[1].id

        await anna.send(.transferHost(to: target))
        try await eventually { anna.successor != nil }
        let retired = anna.successor!
        #expect(!retired.isHost && retired.connection == .reconnecting && retired.state?.phase == .betting)
        #expect(await retired.leave())
        let kept = try #require(save.load())
        #expect(kept.isResumable && kept.game.state.hostID == anna.me)
        await ben.disconnect()
    }

    /// The seat ticket could not be written: the old host's save is then the only way back, so it stays.
    @Test func oldHostKeepsItsSaveWhenTheSeatTicketCannotBeWritten() async throws {
        let name = uniqueName()
        let annaSave: SaveFile<HostSnapshot> = tempFile()
        let annaTicket: SaveFile<SeatTicket> = tempFile()
        try FileManager.default.createDirectory(at: annaTicket.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try setReadOnly(annaTicket, true)
        defer { try? setReadOnly(annaTicket, false) }
        let service = NWEndpoint.service(name: name, type: Wire.serviceType, domain: "local.", interface: nil)
        let anna = try await TableSession.host(
            .newTable(hostName: "Anna", tableName: name, code: code4711, config: .relaxed),
            saveFile: annaSave, ticketFile: annaTicket)
        let ben = await TableSession.join(endpoint: service, tableName: name, code: code4711, name: "Ben",
                                          ticketFile: tempFile(), saveFile: tempFile())
        try await eventually(timeout: .seconds(30)) { anna.state?.seats.count == 2 && ben.me != nil }
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { anna.state?.phase == .betting }

        await anna.send(.transferHost(to: ben.me!))
        try await eventually(timeout: .seconds(30)) { anna.successor != nil && ben.successor != nil }
        let newHost = ben.successor!
        let oldHost = anna.successor!
        defer { Task { await oldHost.leave(); await newHost.leave() } }
        try await eventually(timeout: .seconds(30)) { oldHost.connection == .connected }
        #expect(oldHost.problem?.action == .save)
        #expect(annaSave.load() != nil)
    }

    @Test func failedTakeoverIsShownAndTheGuestStaysAGuest() async throws {
        let anna = try await hostUnique()
        defer { Task { await anna.successor?.leave() } }
        let benSave: SaveFile<HostSnapshot> = tempFile()
        try FileManager.default.createDirectory(at: benSave.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try setReadOnly(benSave, true)
        defer { try? setReadOnly(benSave, false) }
        let ben = await guestSession(anna, saveFile: benSave)
        defer { Task { await ben.leave() } }
        try await eventually { anna.state?.seats.count == 2 && ben.me != nil }
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { anna.state?.phase == .betting && ben.state?.phase == .betting }

        await anna.send(.transferHost(to: ben.me!))
        try await eventually { ben.problem?.action == .listen }
        #expect(ben.successor == nil && !ben.isHost)
        try await eventually { ben.connection == .reconnecting }
    }

    @Test func leavingAsHostStillLeavesTheSeatTicketAlone() async throws {
        let tickets: SaveFile<SeatTicket> = tempFile()
        try tickets.save(SeatTicket(tableName: "Other", code: code4711, name: "Anna", token: "t"))
        let anna = try await hostSession(ticketFile: tickets)
        #expect(await anna.leave())
        #expect(tickets.load()?.tableName == "Other")
    }
}
