import Foundation
import Testing

@testable import SpeakCore

/// A ramp so any dropped, repeated or reordered sample is visible.
private func ramp(_ start: Int, _ count: Int) -> [Float] {
    (0..<count).map { Float(start + $0 + 1) / 100_000 }
}

/// AVAudioPlayerNode applies schedule calls asynchronously; in real time chunks
/// are queued seconds ahead, so give each schedule a moment before pulling audio.
private func settle() async { try? await Task.sleep(nanoseconds: 20_000_000) }

private func waitUntil(_ timeout: Double = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

@Suite("Scheduled player (manual rendering, no device)")
struct PlayerTests {

    @Test func chunksJoinWithoutGaps() async throws {
        let player = ScheduledPlayer(output: .manual, sampleRate: 24_000)
        let gen = try player.begin()
        let a = ramp(0, 6_000), b = ramp(6_000, 9_000), c = ramp(15_000, 3_000)
        player.enqueue(a, generation: gen)
        await settle()
        // The next chunk arrives while the first is still playing.
        try player.render(frames: 4_096)
        player.enqueue(b, generation: gen)
        await settle()
        try player.render(frames: 8_192)
        player.enqueue(c, generation: gen)
        await settle()
        let flag = Flag()
        player.finish(generation: gen) { flag.set() }
        try player.render(frames: 8_192)
        let out = player.renderedSamples
        let expected = a + b + c
        let mismatch = zip(out, expected).enumerated().first { $0.element.0 != $0.element.1 }
        #expect(mismatch == nil, "first mismatch at \(mismatch?.offset ?? -1): \(String(describing: mismatch?.element))")
        #expect(out.count >= expected.count)
        #expect(Array(out.prefix(expected.count)) == expected)
        #expect(await waitUntil { flag.isSet })
        #expect(player.underrunCount(generation: gen) == 0)
        #expect(!player.isActive)
    }

    @Test func lateChunkCountsAsUnderrun() async throws {
        let player = ScheduledPlayer(output: .manual, sampleRate: 24_000)
        let gen = try player.begin()
        player.enqueue(ramp(0, 2_000), generation: gen)
        await settle()
        try player.render(frames: 4_096)  // plays past the end: the queue runs dry
        #expect(player.underrunCount(generation: gen) == 0)
        let late = ramp(2_000, 2_000)
        player.enqueue(late, generation: gen)
        await settle()
        #expect(player.underrunCount(generation: gen) == 1)
        let flag = Flag()
        player.finish(generation: gen) { flag.set() }
        try player.render(frames: 4_096)
        #expect(await waitUntil { flag.isSet })
        // The late chunk starts where the player was, not in the past.
        let out = player.renderedSamples
        #expect(Array(out[4_096..<6_096]) == late)
    }

    @Test func beginReplacesQueuedAudio() async throws {
        let player = ScheduledPlayer(output: .manual, sampleRate: 24_000)
        let first = try player.begin()
        player.enqueue([Float](repeating: 0.5, count: 48_000), generation: first)
        await settle()
        let released = Flag()
        player.finish(generation: first) { released.set() }
        try player.render(frames: 1_024)
        let second = try player.begin()
        // The old session's waiter is released rather than left hanging.
        #expect(await waitUntil { released.isSet })
        // Late chunks for the old session are ignored.
        player.enqueue([Float](repeating: 0.5, count: 1_000), generation: first)
        let fresh = ramp(0, 2_000)
        player.enqueue(fresh, generation: second)
        await settle()
        let before = player.renderedSamples.count
        try player.render(frames: 2_048)
        let after = Array(player.renderedSamples[before...])
        #expect(Array(after.prefix(fresh.count)) == fresh)
    }

    @Test func stopIsImmediate() async throws {
        let player = ScheduledPlayer(output: .manual, sampleRate: 24_000)
        let gen = try player.begin()
        player.enqueue([Float](repeating: 0.5, count: 48_000), generation: gen)
        await settle()
        try player.render(frames: 1_024)
        #expect(player.queuedSeconds > 1.5)
        player.stop()
        #expect(!player.isActive)
        #expect(player.queuedSeconds == 0)
        let before = player.renderedSamples.count
        try player.render(frames: 1_024)
        #expect(player.renderedSamples[before...].allSatisfy { $0 == 0 })
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

@Suite("Protocol and audio helpers")
struct HelperTests {
    @Test func requestRoundTrip() throws {
        let r = SpeakRequest(command: .speak, text: "Hi \"there\"\nnext", voice: "af_bella", speed: 1.2, out: "/tmp/a b.wav")
        let line = try LineCodec.encode(r)
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        #expect(try LineCodec.decode(SpeakRequest.self, from: line.dropLast()) == r)
    }

    @Test func wavRoundTrip() throws {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1, 0.25]
        let data = WAV.data(samples: samples, sampleRate: 24_000)
        #expect(data.count == 44 + samples.count * 2)
        let back = try #require(WAV.read(data))
        #expect(back.sampleRate == 24_000)
        for (x, y) in zip(samples, back.samples) { #expect(abs(x - y) < 0.0001) }
    }

    @Test func chunkShapingTrimsSilenceAndAddsPause() {
        let rate = 24_000
        let silence = [Float](repeating: 0, count: rate)  // 1 s
        let voice = [Float](repeating: 0.3, count: rate / 2)
        let shaped = ChunkAudio.shape(silence + voice + silence, sampleRate: rate, text: "Done.")
        let seconds = Double(shaped.count) / Double(rate)
        // 0.5 s of voice + 20 ms lead + 40 ms tail + 280 ms sentence pause.
        #expect(abs(seconds - 0.84) < 0.01)
        #expect(ChunkAudio.pause(after: "and then,") == 0.12)
        #expect(ChunkAudio.pause(after: "Done.") == 0.28)
        #expect(ChunkAudio.shape(silence, sampleRate: rate, text: "x").isEmpty)
    }

    @Test func voiceCatalog() {
        #expect(VoiceCatalog.voice(VoiceCatalog.defaultVoice)?.grade == "A")
        #expect(VoiceCatalog.all.count == 55)
        #expect(VoiceCatalog.voice("indian")?.id == "af_heart_in")
        #expect(VoiceCatalog.voice("af_heart_in")?.isBlend == true)
        let weights = VoiceCatalog.blends["af_heart_in"]!
        #expect(weights.map(\.voice) == ["af_heart", "hf_alpha"])
        #expect(weights.map(\.weight) == [0.75, 0.25])
        let hindi = VoiceCatalog.all.filter(\.isHindi).map(\.id)
        #expect(hindi == ["hf_alpha", "hf_beta", "hm_omega", "hm_psi"])
        #expect(VoiceCatalog.listing().contains("hm_psi"))
    }
}

/// Fake engine: 0.4 s of tone per chunk, after a short delay.
actor FakeEngine: SpeechEngine {
    nonisolated let sampleRate = 24_000
    nonisolated let name = "fake"
    var calls: [String] = []
    var unloads = 0
    func load() async throws {}
    func unload() async { unloads += 1 }
    func phonemes(for text: String) async throws -> String { text }
    func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float] {
        calls.append(text)
        try await Task.sleep(nanoseconds: 20_000_000)
        return [Float](repeating: 0.2, count: 9_600)
    }
}

final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SpeakEvent] = []
    func add(_ e: SpeakEvent) { lock.withLock { items.append(e) } }
    var all: [SpeakEvent] { lock.withLock { items } }
    var kinds: [SpeakEvent.Kind] { all.map(\.event) }
}

@Suite("Service (fake engine, null output)")
struct ServiceTests {

    private func makeService(output: ScheduledPlayer.Output = .null) -> (SpeakService, FakeEngine) {
        let engine = FakeEngine()
        let player = ScheduledPlayer(output: output, sampleRate: 24_000)
        return (SpeakService(engine: engine, player: player), engine)
    }

    @Test func writesFileWithStats() async throws {
        let (service, engine) = makeService()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speak-test-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let events = Events()
        await service.handle(
            SpeakRequest(command: .speak, text: "# Hi\nIt cost $5. Second sentence here.", out: url.path)
        ) { events.add($0) }
        #expect(events.kinds == [.accepted, .firstAudio, .done])
        let done = try #require(events.all.last)
        #expect(done.chunks == 2)
        #expect((done.audioSeconds ?? 0) > 1)
        let wav = try #require(WAV.read(try Data(contentsOf: url)))
        #expect(wav.sampleRate == 24_000)
        let calls = await engine.calls
        #expect(calls.contains("Hi."))
        #expect(calls.contains { $0.contains("five dollars") })
    }

    @Test func playsThroughNullOutputAndFinishes() async throws {
        let (service, _) = makeService()
        let events = Events()
        await service.handle(SpeakRequest(command: .speak, text: "One. Two. Three.")) { events.add($0) }
        #expect(await waitUntil(10) { events.kinds.contains(.done) })
        #expect(events.kinds == [.accepted, .firstAudio, .done])
        #expect(events.all.last?.underruns == 0)
    }

    @Test func newRequestReplacesAndStopStops() async throws {
        let (service, _) = makeService()
        let first = Events()
        await service.handle(SpeakRequest(command: .speak, text: String(repeating: "Long text here. ", count: 30))) {
            first.add($0)
        }
        #expect(await waitUntil { first.kinds.contains(.firstAudio) })
        let second = Events()
        await service.handle(SpeakRequest(command: .speak, text: String(repeating: "Other text. ", count: 30))) {
            second.add($0)
        }
        #expect(first.kinds.last == .interrupted)
        #expect(await waitUntil { second.kinds.contains(.firstAudio) })
        #expect(await service.status().speaking)
        let stop = Events()
        await service.handle(SpeakRequest(command: .stop)) { stop.add($0) }
        #expect(stop.kinds == [.stopped])
        #expect(second.kinds.last == .interrupted)
        #expect(await service.status().speaking == false)
    }

    @Test func rejectsBadInput() async {
        let (service, _) = makeService()
        let events = Events()
        await service.handle(SpeakRequest(command: .speak, text: "Hi", voice: "nobody")) { events.add($0) }
        await service.handle(SpeakRequest(command: .speak, text: "Hi", speed: 2.5)) { events.add($0) }
        await service.handle(SpeakRequest(command: .speak, text: "🎉")) { events.add($0) }
        #expect(events.kinds == [.error, .error, .error])
    }
}

@Suite("Idle exit")
struct IdleTests {
    @Test func statusDoesNotKeepServerAlive() async {
        var settings = SpeakService.Settings()
        settings.idleTimeout = 0.2
        let service = SpeakService(
            engine: FakeEngine(), player: ScheduledPlayer(output: .manual, sampleRate: 24_000), settings: settings)
        await service.handle(SpeakRequest(command: .stop)) { _ in }
        #expect(await service.shouldExit() == false)
        try? await Task.sleep(nanoseconds: 300_000_000)
        await service.handle(SpeakRequest(command: .status)) { _ in }
        #expect(await service.shouldExit() == true)
    }
}

@Suite("Idle unload")
struct UnloadTests {
    @Test func unloadsAfterIdleAndReloads() async throws {
        var settings = SpeakService.Settings()
        settings.unloadAfter = 0.2
        let engine = FakeEngine()
        let service = SpeakService(
            engine: engine, player: ScheduledPlayer(output: .manual, sampleRate: 24_000), settings: settings)
        await service.handle(SpeakRequest(command: .phonemes, text: "Hi.")) { _ in }
        #expect(await service.status().modelState == "ready")
        #expect(await service.unloadIfIdle() == false)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(await service.unloadIfIdle() == true)
        #expect(await engine.unloads == 1)
        #expect(await service.status().modelState.hasPrefix("unloaded"))
        #expect(await service.unloadIfIdle() == false)
        await service.handle(SpeakRequest(command: .phonemes, text: "Hi.")) { _ in }
        #expect(await service.status().modelState == "ready")
    }
}

@Suite("install-skill")
struct SkillInstallerTests {
    private func tempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speak-home-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test func claudeAndOpenCodeSkillsAreIdempotent() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = SkillInstaller(environment: ["HOME": home.path])
        for target in [SkillInstaller.Target.claude, .opencode, .deepseek] {
            let url = installer.path(for: target)
            #expect(try installer.install(target).contains("installed"))
            #expect(try installer.install(target).contains("already up to date"))
            let text = try #require(read(url))
            #expect(text.hasPrefix("---\nname: speak\ndescription: "))
            #expect(text.contains("speak --stop"))
            #expect(try installer.uninstall(target).contains("removed"))
            #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
            #expect(try installer.uninstall(target).contains("not installed"))
        }
        #expect(installer.path(for: .claude).path == home.path + "/.claude/skills/speak/SKILL.md")
        #expect(installer.path(for: .opencode).path == home.path + "/.config/opencode/skills/speak/SKILL.md")
        #expect(installer.path(for: .deepseek).path == home.path + "/.deepseek/skills/speak/SKILL.md")
    }

    @Test func geminiSectionKeepsTheRestOfTheFile() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = SkillInstaller(environment: ["HOME": home.path])
        let url = installer.path(for: .gemini)
        #expect(url.path == home.path + "/.gemini/GEMINI.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# My notes\nKeep this line.\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(try installer.install(.gemini).contains("updated"))
        #expect(try installer.install(.gemini).contains("already up to date"))
        let text = try #require(read(url))
        #expect(text.contains("Keep this line.") && text.contains("speak --stop"))
        #expect(try installer.uninstall(.gemini).contains("removed"))
        #expect(try #require(read(url)).contains("Keep this line.") && !(try #require(read(url))).contains("speak --stop"))
    }

    @Test func claudeConfigDirFromFlagOrEnvironment() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = SkillInstaller(environment: ["HOME": home.path, "CLAUDE_CONFIG_DIR": "~/.claude-two"])
        #expect(env.path(for: .claude).path == home.path + "/.claude-two/skills/speak/SKILL.md")
        let flag = SkillInstaller(environment: env.environment, claudeConfigDir: home.path + "/three")
        #expect(flag.path(for: .claude).path == home.path + "/three/skills/speak/SKILL.md")
    }

    @Test func leavesSomeoneElsesSkillAlone() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = SkillInstaller(environment: ["HOME": home.path])
        let url = installer.path(for: .claude)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "mine".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: SkillInstaller.InstallError.self) { try installer.install(.claude) }
        #expect(throws: SkillInstaller.InstallError.self) { try installer.uninstall(.claude) }
        #expect(read(url) == "mine")
    }

    @Test func codexSectionAppendsReplacesAndRemoves() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = SkillInstaller(environment: ["HOME": home.path])
        let url = installer.path(for: .codex)
        #expect(url.path == home.path + "/.codex/AGENTS.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "# My rules\n\nBe brief.\n"
        try original.write(to: url, atomically: true, encoding: .utf8)

        _ = try installer.install(.codex)
        let once = try #require(read(url))
        #expect(once.hasPrefix(original + "\n<!-- BEGIN speak"))
        #expect(once.hasSuffix("<!-- END speak -->\n"))
        #expect(try installer.install(.codex).contains("already up to date"))

        // A stale section is replaced in place, and text after it is kept.
        let stale = once.replacingOccurrences(of: "speak --stop", with: "old") + "\nAfter.\n"
        try stale.write(to: url, atomically: true, encoding: .utf8)
        _ = try installer.install(.codex)
        let replaced = try #require(read(url))
        #expect(replaced == once + "\nAfter.\n")
        #expect(replaced.components(separatedBy: "<!-- BEGIN speak").count == 2)

        _ = try installer.uninstall(.codex)
        #expect(read(url) == original + "\nAfter.\n")

        // A file holding only the section is deleted on uninstall.
        try FileManager.default.removeItem(at: url)
        _ = try installer.install(.codex)
        _ = try installer.uninstall(.codex)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func repositoryCopiesMatch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        #expect(read(root.appendingPathComponent("skills/claude-code/speak/SKILL.md")) == SkillTexts.skill)
        #expect(read(root.appendingPathComponent("skills/generic.md")) == SkillTexts.generic)
    }
}
