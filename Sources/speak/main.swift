import Darwin
import Foundation
import SpeakCore
import SpeakNormalizer

let usage = """
    speak: read text aloud with Kokoro-82M, on device.

    Usage:
      speak "text"                 speak the text (replaces anything already playing)
      speak --file notes.md        speak a file
      echo "text" | speak          speak standard input
      speak --out reply.wav "text" write a WAV file instead of playing
      speak --stop                 stop playback at once
      speak --status               show the server's state
      speak --voices               list voices
      speak serve                  run the server in the foreground (normally started for you)
      speak install-skill --claude | --codex | --opencode | --deepseek | --gemini | --all | --print
                                   teach a coding agent to read answers aloud (see below)

    Options:
      --voice, -v <id>     voice (default af_heart; see --voices)
      --speed, -s <x>      0.8 to 1.6 (default 1.1)
      --wait, -w           wait until playback finishes
      --raw                speak the text exactly, without normalising it
      --normalize          print the normalised text and its chunks, without speaking
      --phonemes           print the phonemes the engine would speak, per chunk
      --json               print server events as JSON lines
      --shutdown           stop the server
      --version, --help

    install-skill:
      --claude             Claude Code skill in ~/.claude/skills/speak (or $CLAUDE_CONFIG_DIR)
      --config-dir <dir>   Claude Code config folder instead; repeat for several accounts
      --codex              a marked section in ~/.codex/AGENTS.md (or $CODEX_HOME)
      --opencode           OpenCode skill in ~/.config/opencode/skills/speak
      --deepseek           DeepSeek-TUI skill in ~/.deepseek/skills/speak
      --gemini             a marked section in ~/.gemini/GEMINI.md
      --all                every harness above
      --print              print the instructions for any other harness
      --uninstall          remove what install-skill wrote
      Running it again updates in place.

    The server keeps the model warm on a Unix socket under
    ~/Library/Application Support/speak, unloads the model after 15 minutes
    idle and exits after 30.
    """

struct Options {
    var text: [String] = []
    var file: String?
    var voice: String?
    var speed: Double?
    var out: String?
    var wait = false
    var raw = false
    var json = false
    var action: Action = .speak
}

enum Action { case speak, stop, status, voices, normalize, phonemes, shutdown, serve, help, version }

/// `speak install-skill ...`. Never returns.
func installSkill(_ args: [String]) -> Never {
    var targets: [SkillInstaller.Target] = []
    var configDirs: [String] = []
    var uninstall = false
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--claude": targets.append(.claude)
        case "--codex": targets.append(.codex)
        case "--opencode": targets.append(.opencode)
        case "--deepseek": targets.append(.deepseek)
        case "--gemini": targets.append(.gemini)
        case "--all": targets = SkillInstaller.Target.allCases
        case "--uninstall": uninstall = true
        case "--config-dir", "--claude-config-dir":
            i += 1
            guard i < args.count else { die("--config-dir needs a folder") }
            configDirs.append(args[i])
            if !targets.contains(.claude) { targets.append(.claude) }
        case "--print":
            print(SkillTexts.generic, terminator: "")
            exit(0)
        case "--print-skill":
            print(SkillTexts.skill, terminator: "")
            exit(0)
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            die("unknown install-skill option \(args[i]); use --claude, --codex, --opencode, --deepseek, --gemini, --all or --print")
        }
        i += 1
    }
    guard !targets.isEmpty else { die("install-skill needs --claude, --codex, --opencode, --deepseek, --gemini, --all or --print") }
    var failed = false
    for target in targets {
        let dirs: [String?] = target == .claude && !configDirs.isEmpty ? configDirs : [nil]
        for dir in dirs {
            let installer = SkillInstaller(claudeConfigDir: dir)
            do {
                print(uninstall ? try installer.uninstall(target) : try installer.install(target))
            } catch {
                FileHandle.standardError.write(Data("speak: \(error)\n".utf8))
                failed = true
            }
        }
    }
    exit(failed ? 1 : 0)
}

func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("speak: \(message)\n".utf8))
    exit(code)
}

func parse(_ args: [String]) -> Options {
    var o = Options()
    var i = 0
    func value(_ flag: String) -> String {
        i += 1
        guard i < args.count else { die("\(flag) needs a value") }
        return args[i]
    }
    if args.first == "install-skill" { installSkill(Array(args.dropFirst())) }
    if args.first == "serve" {
        o.action = .serve
        return o
    }
    var literal = false
    while i < args.count {
        let a = args[i]
        if literal {
            o.text.append(a)
        } else {
            switch a {
            case "--": literal = true
            case "--file", "-f": o.file = value(a)
            case "--voice", "-v": o.voice = value(a)
            case "--speed", "-s":
                let v = value(a)
                guard let d = Double(v) else { die("--speed needs a number, got '\(v)'") }
                o.speed = d
            case "--out", "-o": o.out = value(a)
            case "--wait", "-w": o.wait = true
            case "--raw": o.raw = true
            case "--json": o.json = true
            case "--stop": o.action = .stop
            case "--status": o.action = .status
            case "--voices": o.action = .voices
            case "--normalize", "--normalise": o.action = .normalize
            case "--phonemes": o.action = .phonemes
            case "--shutdown": o.action = .shutdown
            case "--help", "-h": o.action = .help
            case "--version": o.action = .version
            default:
                if a.hasPrefix("-"), a.count > 1, Double(a) == nil { die("unknown option \(a); see speak --help") }
                o.text.append(a)
            }
        }
        i += 1
    }
    return o
}

func readInput(_ o: Options) -> String {
    if let file = o.file {
        let path = (file as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path), let s = String(data: data, encoding: .utf8) else {
            die("cannot read \(file)")
        }
        return s
    }
    if !o.text.isEmpty { return o.text.joined(separator: " ") }
    if isatty(STDIN_FILENO) == 0 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
    die("nothing to say; see speak --help")
}

func printJSON(_ event: SpeakEvent) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if let d = try? enc.encode(event), let s = String(data: d, encoding: .utf8) { print(s) }
    fflush(stdout)
}

func fmt(_ v: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", v) }

func printStatus(_ s: ServerStatus) {
    print("""
        server      running, pid \(s.pid), version \(s.version)
        engine      \(s.engine)
        model       \(s.modelState)\(s.modelLoadSeconds.map { " (loaded in \(fmt($0)) s)" } ?? "")
        audio       \(s.audioOutput)
        voice       \(s.defaultVoice)
        speaking    \(s.speaking ? "yes" + (s.currentChunk.map { ", chunk \($0) of \(s.totalChunks ?? 0)" } ?? "") + ", \(fmt(s.queuedAudioSeconds, 1)) s queued" : "no")
        idle        \(Int(s.idleSeconds)) s (\(s.unloadAfterSeconds.map { "unloads the model after \(Int($0)) s, " } ?? "")exits after \(Int(s.idleTimeoutSeconds)) s)
        fast path   \(s.slowPathChunks.map { $0 == 0 ? "every chunk" : "\($0) chunks were too long for it" } ?? "n/a")
        memory      \(fmt(s.footprintMB, 0)) MB footprint, \(fmt(s.residentMB, 0)) MB resident
        uptime      \(Int(s.uptimeSeconds)) s, \(s.requestsServed) requests
        """)
}

var sigintSource: DispatchSourceSignal?
let options = parse(Array(CommandLine.arguments.dropFirst()))
let client = SpeakClient()

switch options.action {
case .help:
    print(usage)
case .version:
    print("speak \(SpeakService.version)")
case .serve:
    SpeakServer.run()
case .voices:
    print(VoiceCatalog.listing())
case .normalize:
    let normalized = TextNormalizer.normalize(readInput(options))
    print(normalized)
    print("\n-- chunks --")
    let fastPath = ProcessInfo.processInfo.environment["SPEAK_KOKORO"] == "v3"
    for (i, c) in SpeechChunker.forKokoro(speed: options.speed ?? 1.1, fastPathOnly: fastPath).chunks(normalized).enumerated() {
        print("\(i + 1). [\(c.count)] \(c)")
    }
case .phonemes:
    let request = SpeakRequest(command: .phonemes, text: readInput(options), raw: options.raw ? true : nil)
    do {
        try client.send(request, autostart: true) { e in
            if e.event == .error { die(e.message ?? "error") }
            if let m = e.message { print(m) }
            return false
        }
    } catch {
        die("\(error)")
    }
case .status:
    do {
        try client.send(SpeakRequest(command: .status), autostart: false) { e in
            if options.json { printJSON(e) } else if let s = e.status { printStatus(s) }
            return false
        }
    } catch SpeakClient.ClientError.notRunning {
        print("server      not running (starts on the next speak)")
    } catch {
        die("\(error)")
    }
case .stop, .shutdown:
    do {
        try client.send(SpeakRequest(command: options.action == .stop ? .stop : .shutdown), autostart: false) { e in
            if options.json { printJSON(e) }
            return false
        }
    } catch SpeakClient.ClientError.notRunning {
        // Nothing playing.
    } catch {
        die("\(error)")
    }
case .speak:
    let text = readInput(options)
    if let v = options.voice, VoiceCatalog.voice(v) == nil { die("unknown voice '\(v)'; run speak --voices") }
    if let s = options.speed, !SpeakService.speedRange.contains(s) { die("--speed must be between 0.8 and 1.6") }
    var out: String?
    if let o = options.out {
        let expanded = (o as NSString).expandingTildeInPath
        out = URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.path
    }
    let request = SpeakRequest(
        command: .speak, text: text, voice: options.voice, speed: options.speed, out: out,
        raw: options.raw ? true : nil)
    let waitForEnd = options.wait || out != nil

    // Ctrl-C while waiting stops the speech too.
    if options.wait, out == nil {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler {
            try? client.send(SpeakRequest(command: .stop), autostart: false) { _ in false }
            exit(130)
        }
        source.resume()
        sigintSource = source
    }

    var failed: String?
    do {
        try client.send(request, autostart: true) { e in
            if options.json { printJSON(e) }
            switch e.event {
            case .accepted:
                return true
            case .firstAudio:
                return waitForEnd
            case .done:
                if !options.json, let path = e.path, let audio = e.audioSeconds, let synth = e.synthSeconds {
                    print("wrote \(path): \(fmt(audio)) s of audio in \(fmt(synth)) s (real-time factor \(fmt(synth / max(audio, 0.001), 3)))")
                }
                return false
            case .error:
                failed = e.message ?? "error"
                return false
            default:
                return false
            }
        }
    } catch {
        die("\(error)")
    }
    if let failed { die(failed) }
}
