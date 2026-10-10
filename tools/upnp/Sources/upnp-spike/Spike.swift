import Foundation
import UPnPCommon

struct Snapshot: CustomStringConvertible {
    var state = "?"
    var status = "?"
    var relText = "?"
    var durationText = "?"
    var uri = ""
    var track = "?"

    var rel: Double? { parseTime(relText) }
    var duration: Double? { parseTime(durationText) }
    var uriName: String { uri.isEmpty ? "-" : (URL(string: uri)?.lastPathComponent ?? uri) }
    var description: String { "\(state) \(relText)/\(durationText) track=\(track) uri=\(uriName) status=\(status)" }
}

/// How the first play went — the guided test picks its next step from it.
enum PlayOutcome {
    case played
    /// SetAVTransportURI or Play answered with an error.
    case refused
    /// The renderer fetched the file but never reported PLAYING.
    case fetchedButSilent
    /// The renderer never asked for the file: firewall, VPN or another network.
    case neverFetched
}

@MainActor
final class Spike {
    private let server: MediaServer
    private var devices: [UPnPDevice] = []
    private var device: UPnPDevice?
    private var localIP = "127.0.0.1"
    private var sendMetadata = true
    private var watchTask: Task<Void, Never>?
    private var subscriptions: [(url: URL, sid: String)] = []
    private var results: [String] = []
    private var lastSearchError: String?
    private var testFiles: TestFiles.Set?
    /// The guided test: German prompts on the terminal, the details only in the log.
    private var guided = false
    private var interrupt: DispatchSourceSignal?
    /// Keeps the Mac from idle sleep while nobody touches it during the long steps.
    private var awake: NSObjectProtocol?
    /// A ready-made SOAP Stop for the ctrl-C handler, which cannot wait for the main actor.
    nonisolated(unsafe) private static var stopRequest: URLRequest?
    /// Show the result zip in the Finder at the end (off for scripted runs).
    nonisolated(unsafe) static var revealsResults = true

    init(port: UInt16) throws {
        server = MediaServer(preferredPort: port)
        try server.start()
    }

    // MARK: - Guided test (the default)

    /// For the person next to the renderer: five steps, German on the terminal, everything else
    /// in the log, and a zip of the run next to the program at the end.
    func runGuided(descriptionURL: String?) async {
        guided = true
        installInterruptHandler()
        awake = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                       reason: "Devialet test running")
        results = ["Audio Harbor UPnP test, \(ISO8601DateFormatter().string(from: Date()))",
                   "Mac: macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(Self.architecture)", ""]
        writeSummary()
        tell("""

        ──────────────────────────────────────────────────────
          Devialet-Test für Audio Harbor
        ──────────────────────────────────────────────────────
        Das Programm prüft, wie der Devialet Musik vom Mac über das
        Netzwerk annimmt. Es dauert etwa 6 Minuten; der Devialet
        spielt dabei leise Testtöne. Abbrechen: ctrl + C.

        """)
        tell("Vorbereitung: Testtöne erzeugen …")
        let files: TestFiles.Set
        do {
            files = try TestFiles.make(in: FileManager.default.temporaryDirectory
                .appendingPathComponent("devialet-test-\(UUID().uuidString)"))
        } catch {
            note("Test files: \(error)")
            tell("Die Testtöne ließen sich nicht erzeugen (\(error)).")
            await finish()
            return
        }
        testFiles = files
        for skipped in files.skipped { note("Test file skipped — \(skipped)") }
        tell("   fertig")

        _ = await ask("\nBitte stell den Verstärker jetzt leise und drück dann Enter.")

        tell("\nSchritt 1 von 5 · Devialet suchen")
        guard await findDevialet(descriptionURL: descriptionURL) else {
            await finish()
            return
        }

        tell("\nSchritt 2 von 5 · Grundfunktionen (etwa 1 Minute)")
        tell("   Ein Ton startet, pausiert kurz und springt. Du musst nichts tun.")
        var outcome = (try? await auto(files.seek.path, files.gaplessSecond.path)) ?? .refused
        while outcome == .neverFetched {
            tell("   Der Devialet hat die Testdatei nicht vom Mac abgeholt. Meist blockiert")
            tell("   die Firewall des Macs (Systemeinstellungen → Netzwerk → Firewall) oder")
            tell("   ein VPN die Verbindung: Firewall kurz ausschalten oder VPN trennen.")
            if await ask("   Enter = nochmal versuchen · q = beenden") == "q" { break }
            outcome = (try? await auto(files.seek.path, files.gaplessSecond.path)) ?? .refused
        }

        switch outcome {
        case .played:
            tell("   ✓ erledigt")
            tell("\nSchritt 3 von 5 · Lautstärkeregler")
            await knobTest()
            tell("\nSchritt 4 von 5 · Übergang zwischen zwei Dateien (etwa 30 Sekunden)")
            await gaplessTest(files.gaplessFirst, files.gaplessSecond)
            tell("\nSchritt 5 von 5 · Formate (etwa 3 Minuten)")
            await formatsGuided(files.formats)
        case .refused, .fetchedButSilent:
            note("Steps 3–4 skipped: the first file did not play")
            tell("   Diese Datei hat der Devialet nicht gespielt. Ich probiere andere Formate.")
            tell("\nSchritt 5 von 5 · Formate (etwa 3 Minuten)")
            await formatsGuided(files.formats)
        case .neverFetched:
            note("Stopped: the renderer never fetched a file")
        }
        await finish()
    }

    private func findDevialet(descriptionURL: String?) async -> Bool {
        if let descriptionURL {
            do {
                try await open(descriptionURL)
                tell("   Verbunden: \(device?.friendlyName ?? descriptionURL)")
                return true
            } catch {
                note("Open \(descriptionURL): \(error)")
                tell("   Unter \(descriptionURL) antwortet kein Abspielgerät.")
                return false
            }
        }
        while true {
            tell("   Suche im Netzwerk …")
            await discover(seconds: 6)
            note("Search: \(devices.count) renderer(s)" + devices.map { "\n  \($0.summary)" }.joined())
            if let found = device, Self.isDevialet(found) {
                tell("   Gefunden: \(found.friendlyName) (\(found.address))")
                return true
            }
            if let found = device, devices.count == 1 {
                tell("   Gefunden: \(found.friendlyName) – \(found.manufacturer) \(found.modelName) (\(found.address))")
                let answer = await ask("   Ist das der Devialet?  j = ja · n = nein")
                if answer.hasPrefix("j") || answer.hasPrefix("y") {
                    note("Renderer confirmed by the tester: \(found.summary)")
                    return true
                }
                device = nil
            } else if devices.count > 1 {
                tell("   Mehrere Abspielgeräte gefunden:")
                for (index, candidate) in devices.enumerated() {
                    tell("     \(index + 1). \(candidate.friendlyName) – \(candidate.manufacturer) \(candidate.modelName) (\(candidate.address))")
                }
                let answer = await ask("   Welche Nummer ist der Devialet?  (Enter = keiner davon)")
                if let number = Int(answer), devices.indices.contains(number - 1) {
                    select(devices[number - 1])
                    note("Renderer picked by the tester: \(devices[number - 1].summary)")
                    return true
                }
            }
            if let lastSearchError {
                tell("   macOS hat die Suche blockiert (\(lastSearchError)).")
            }
            tell("""
               Ich finde den Devialet nicht. Bitte prüfe:
               • Ist der Devialet eingeschaltet?
               • Sind Mac und Devialet im selben Netzwerk (kein Gast-WLAN, kein VPN)?
               • Ab macOS 15: Darf Terminal ins lokale Netzwerk? Systemeinstellungen →
                 Datenschutz & Sicherheit → Lokales Netzwerk → Terminal einschalten.
               • Ist UPnP im Devialet eingeschaltet?
            """)
            if await ask("   Enter = nochmal suchen · q = beenden") == "q" {
                note("Search: given up, no Devialet found")
                return false
            }
        }
    }

    /// Does the volume the control point reads follow the remote or the knob, and are there events?
    private func knobTest() async {
        guard let start = try? await volume(quiet: true) else {
            note("Knob: GetVolume not available — skipped")
            tell("   Übersprungen – der Devialet meldet keine Lautstärke.")
            return
        }
        _ = await ask("   Nimm die Fernbedienung (oder geh an den Regler) und drück Enter, wenn du bereit bist.")
        tell("   Jetzt 15 Sekunden lang etwas lauter und wieder leiser drehen – zum Schluss bitte wieder leise.")
        let began = Date()
        var values = [start]
        while Date().timeIntervalSince(began) < 15 {
            if let level = try? await volume(quiet: true), level != values.last {
                values.append(level)
                say("knob: volume \(level)")
            }
            await sleep(0.4)
        }
        let events = server.events(since: began).filter { $0.path.contains("RenderingControl") }.count
        let moved = values.count > 1
        note("Knob: GetVolume " + values.map(String.init).joined(separator: " → ") + (moved ? "" : " (no change)")
             + "; RenderingControl events in the window: \(events)")
        tell(moved ? "   ✓ Änderung erkannt" : "   Keine Änderung gesehen – auch das ist ein Ergebnis.")
    }

    /// Two files cut from one continuous tone. With SetNext the renderer should run on without a
    /// gap; without it, the app's fallback is SetAVTransportURI + Play after STOPPED — timed here.
    private func gaplessTest(_ first: URL, _ second: URL) async {
        tell("   Ein Ton läuft; nach etwa 10 Sekunden wechselt der Devialet zur zweiten Datei.")
        tell("   Hör genau hin: Der Ton sollte ohne Unterbrechung weiterlaufen.")
        _ = try? await avt("Stop", quiet: true)
        let a: Registered
        do {
            a = try await play(first.path)
        } catch {
            note("Gapless: first file refused — \(error)")
            tell("   Übersprungen – der Devialet hat die Datei nicht angenommen.")
            return
        }
        guard await waitFor(timeout: 15, { $0.state == "PLAYING" }) != nil else {
            note("Gapless: first file did not start")
            tell("   Übersprungen – der Devialet hat nicht angefangen zu spielen.")
            return
        }
        var b: Registered?
        do {
            b = try await setNext(second.path)
            note("Gapless: SetNextAVTransportURI accepted")
        } catch {
            note("Gapless: SetNextAVTransportURI refused — \(error)")
        }
        let duration = (try? await snapshot())?.duration ?? a.info.duration ?? 30
        var window = 22.0
        do {
            try await seek(max(0, duration - 10))
        } catch {
            note("Gapless: seek refused, playing to the end — \(error)")
            window = duration + 8
        }

        var transitions: [String] = []
        var last = ""
        var lastRel: Double?
        var stoppedSince: Date?
        var switchedAt: Date?
        var fallbackGap: Double?
        let began = Date()
        while Date().timeIntervalSince(began) < window {
            if let switchedAt, Date().timeIntervalSince(switchedAt) > 3 { break }
            guard let s = try? await snapshot() else {
                await sleep(0.25)
                continue
            }
            let key = "\(s.state) uri=\(s.uriName)"
            if key != last {
                transitions.append(String(format: "+%.2f s ", Date().timeIntervalSince(began)) + "\(key) rel=\(s.relText)")
                last = key
            }
            if switchedAt == nil {
                let onSecond = b.map { s.uriName == $0.name } ?? false
                // Some renderers keep reporting the first URI and only restart the clock.
                let restarted = s.state == "PLAYING" && (lastRel ?? 0) > 15 && (s.rel ?? 99) < 5
                if onSecond || restarted {
                    switchedAt = Date()
                    tell("   → jetzt gewechselt")
                } else if s.state == "STOPPED" || s.state == "NO_MEDIA_PRESENT", Date().timeIntervalSince(began) > 2 {
                    let since = stoppedSince ?? Date()
                    stoppedSince = since
                    // A renderer that took SetNext gets two seconds to go on by itself; then the app's way.
                    if Date().timeIntervalSince(since) >= (b == nil ? 0 : 2) {
                        if (try? await play(second.path)) != nil, await waitFor(timeout: 10, { $0.state == "PLAYING" }) != nil {
                            fallbackGap = Date().timeIntervalSince(since)
                        }
                        switchedAt = Date()
                        tell("   → jetzt gewechselt")
                    }
                } else {
                    stoppedSince = nil
                }
            }
            if let rel = s.rel { lastRel = rel }
            await sleep(0.25)
        }
        _ = try? await avt("Stop", quiet: true)
        note("Gapless transitions: " + transitions.joined(separator: " | "))
        if let fallbackGap {
            note(String(format: "Gapless: no switch on its own — STOPPED, then SetAVTransportURI + Play: %.1f s until PLAYING", fallbackGap))
        } else if switchedAt != nil {
            let stopped = transitions.contains { $0.contains(" STOPPED ") || $0.contains("NO_MEDIA") }
            note(stopped ? "Gapless: switched, with STOPPED in between" : "Gapless: switched without STOPPED")
        } else {
            note("Gapless: no switch seen")
            tell("   Kein Wechsel erkannt – auch das ist ein Ergebnis.")
            return
        }
        let answer = await ask("   Hast du beim Wechsel eine kurze Stille oder ein Knacken gehört?\n   j = ja · n = nein · ? = nicht sicher")
        note("Gapless by ear: " + (answer.isEmpty || answer == "q" ? "(no answer)" : answer))
    }

    private func formatsGuided(_ folder: URL) async {
        tell("   Der Devialet spielt kurze Töne in verschiedenen Formaten. Manche kann er")
        tell("   vielleicht nicht – das ist in Ordnung. Du musst nichts tun.")
        do {
            try await formats(folder.path)
        } catch {
            note("Formats: \(error)")
        }
    }

    private func finish() async {
        if device != nil { _ = try? await avt("Stop", quiet: true) }
        await unsubscribe()
        if let testFiles { try? FileManager.default.removeItem(at: testFiles.directory) }
        if let awake { ProcessInfo.processInfo.endActivity(awake) }
        writeSummary()
        say("finished")
        guard let zip = Self.zipResults() else {
            tell("\nFertig – vielen Dank! Bitte schick den Ordner \(Log.shared.directory.path) zurück.")
            return
        }
        tell("""

        Fertig – vielen Dank!
        Bitte schick diese Datei zurück:  \(zip.lastPathComponent)
        Sie liegt hier:  \(zip.deletingLastPathComponent().path)
        \(Self.revealsResults ? "Der Finder zeigt sie gleich an." : "")

        """)
        Self.revealInFinder(zip)
    }

    /// The answer, lower-cased; "q" once the input has ended (ctrl-D, a closed pipe), so no
    /// loop waits for an Enter that cannot come.
    private func ask(_ question: String) async -> String {
        tell(question)
        prompt()
        guard let answer = await Self.readLineAsync() else {
            tell("")
            Log.shared.write("answer: (input closed)", terminal: false)
            return "q"
        }
        Log.shared.write("answer: \(answer)", terminal: false)
        return answer.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func note(_ line: String) {
        say("RESULT: \(line)")
        results.append(line)
        writeSummary()
    }

    /// Rewritten on every note, so a run that is cut off still leaves its summary.
    private func writeSummary() {
        Log.shared.save("summary.txt", Data(results.joined(separator: "\n").utf8), quiet: true)
    }

    private func installInterruptHandler() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler {
            say("interrupted (ctrl-C)")
            tell("\n\nAbgebrochen – ich halte den Devialet an und speichere, was bis hierher gemessen wurde …")
            Spike.sendStop()
            if let zip = Spike.zipResults() {
                tell("Bitte trotzdem diese Datei zurückschicken:  \(zip.path)\n")
                Spike.revealInFinder(zip)
            }
            exit(130)
        }
        source.resume()
        interrupt = source
    }

    nonisolated private static func sendStop() {
        guard let request = stopRequest else { return }
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 2)
    }

    nonisolated static func zipResults() -> URL? {
        let directory = Log.shared.directory
        let zip = directory.appendingPathExtension("zip")
        try? FileManager.default.removeItem(at: zip)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", directory.path, zip.path]
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? zip : nil
    }

    nonisolated static func revealInFinder(_ url: URL) {
        guard revealsResults else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-R", url.path]
        try? process.run()
    }

    // MARK: - Interactive

    func runInteractive() async {
        say("Audio Harbor UPnP spike — everything is logged to \(Log.shared.directory.path)")
        printHelp()
        await discover(seconds: 5)
        prompt()
        while let line = await Self.readLineAsync() {
            let words = Self.tokens(line)
            guard let command = words.first?.lowercased() else {
                prompt()
                continue
            }
            Log.shared.write("> \(line)", terminal: false)
            if command == "quit" || command == "q" { break }
            do {
                try await execute(command, Array(words.dropFirst()))
            } catch {
                say("ERROR: \(error)")
            }
            prompt()
        }
        watchTask?.cancel()
        _ = try? await avt("Stop", quiet: true)
        await unsubscribe()
        say("Done. Please send the folder \(Log.shared.directory.path)")
    }

    private func execute(_ command: String, _ args: [String]) async throws {
        switch command {
        case "help", "?": printHelp()
        case "discover": await discover(seconds: Double(args.first ?? "") ?? 5)
        case "list": listDevices()
        case "open": try await open(try argument(args, 0, "open <description URL>"))
        case "use":
            guard let index = Int(args.first ?? ""), devices.indices.contains(index - 1) else {
                throw ToolError("use <number from list>")
            }
            select(devices[index - 1])
        case "info": try await info()
        case "play": try await play(try argument(args, 0, "play <file>"))
        case "next": try await setNext(try argument(args, 0, "next <file>"))
        case "pause": try await avt("Pause")
        case "resume": try await avt("Play", [("Speed", "1")])
        case "stop": try await avt("Stop")
        case "seek":
            guard let seconds = Double(args.first ?? "") else { throw ToolError("seek <seconds>") }
            try await seek(seconds)
        case "pos": say("now: \(try await snapshot(quiet: false))")
        case "vol", "vol!":
            if let level = Int(args.first ?? "") {
                try await setVolume(level, force: command == "vol!")
            } else {
                say("volume: \(try await volume())")
            }
        case "watch":
            if args.first == "off" {
                watchTask?.cancel()
                watchTask = nil
                say("watch off")
            } else {
                startWatch()
            }
        case "subscribe": await subscribe()
        case "meta":
            sendMetadata = args.first != "off"
            say("DIDL-Lite metadata: \(sendMetadata ? "on" : "off (empty CurrentURIMetaData)")")
        case "mime":
            server.mimeOverride = (args.first == nil || args.first == "auto") ? nil : args.first
            say("MIME type: \(server.mimeOverride ?? "by file extension")")
        case "formats": try await formats(try argument(args, 0, "formats <folder>"))
        case "auto": try await auto(try argument(args, 0, "auto <file> [next file]"), args.count > 1 ? args[1] : nil)
        default: say("unknown command \"\(command)\" — type help")
        }
    }

    private func argument(_ args: [String], _ index: Int, _ usage: String) throws -> String {
        guard args.indices.contains(index) else { throw ToolError(usage) }
        return args[index]
    }

    private func printHelp() {
        say("""
        Commands:
          discover [s]       search the network again (default 5 s)
          list / use <n>     show renderers / pick one
          open <url>         use the renderer at a description URL, without SSDP
          info               protocol info (formats), transport + volume state
          auto <a> [<b>]     scripted test: play, pause, seek, volume, end of track, next track
          formats <folder>   play every audio file in a folder for a few seconds, table of results
          play <file>        SetAVTransportURI + Play          next <file>   SetNextAVTransportURI
          pause / resume / stop / seek <s> / pos
          vol [n]            read / set volume (refuses more than +5 over current; vol! n forces)
          watch [off]        log transport state changes every second
          subscribe          GENA events for AVTransport + RenderingControl
          meta on|off        send DIDL-Lite metadata (default on)
          mime <type>|auto   send another Content-Type (e.g. audio/x-flac)
          quit
        Paths: drag a file from Finder into the terminal.
        """)
    }

    private func prompt() {
        FileHandle.standardOutput.write(Data("> ".utf8))
    }

    // MARK: - Discovery

    private func discover(seconds: Double) async {
        say("discover: searching for \(Int(seconds)) s …")
        let (responses, sendError) = await Task.detached {
            SSDP.search(seconds: seconds, targets: [
                "urn:schemas-upnp-org:device:MediaRenderer:1",
                "urn:schemas-upnp-org:service:AVTransport:1",
                "ssdp:all",
            ])
        }.value
        lastSearchError = sendError
        var byLocation: [String: SSDPResponse] = [:]
        for response in responses {
            if let location = response.location, byLocation[location] == nil { byLocation[location] = response }
        }
        say("discover: \(responses.count) answers from \(byLocation.count) devices")
        if responses.isEmpty {
            say("  Nothing answered. Check System Settings → Privacy & Security → Local Network for your terminal app.")
        }

        var found: [UPnPDevice] = []
        for (location, response) in byLocation.sorted(by: { $0.key < $1.key }) {
            if let candidate = await describe(location, address: response.address, server: response.headers["SERVER"] ?? "") {
                found.append(candidate)
            }
        }
        devices = found
        listDevices()
        if device == nil || !devices.contains(where: { $0.udn == device?.udn }) {
            if let pick = devices.first(where: Self.isDevialet) ?? (devices.count == 1 ? devices.first : nil) {
                select(pick)
            } else if !devices.isEmpty {
                say("Several renderers — pick one with: use <n>")
            }
        }
    }

    /// Without SSDP: straight to a description URL (multicast blocked, or a renderer on another subnet).
    private func open(_ location: String) async throws {
        guard let url = URL(string: location), let host = url.host else {
            throw ToolError("open http://<ip>:<port>/<description>.xml")
        }
        guard let candidate = await describe(location, address: host, server: "(opened by URL)") else {
            throw ToolError("no renderer at \(location)")
        }
        devices.removeAll { $0.udn == candidate.udn }
        devices.append(candidate)
        select(candidate)
    }

    /// Fetches a device description and its SCPDs; nil unless it is a renderer.
    private func describe(_ location: String, address: String, server: String) async -> UPnPDevice? {
        guard let url = URL(string: location) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 5))
            var candidate = DescriptionParser.parse(data, into: UPnPDevice(location: url, address: address, server: server))
            say("  \(candidate.isRenderer ? "RENDERER" : "other   ") \(candidate.summary)")
            guard candidate.isRenderer else { return nil }
            let tag = Self.fileSafe(candidate.friendlyName.isEmpty ? address : candidate.friendlyName)
            Log.shared.save("description-\(tag).xml", data)
            for index in candidate.services.indices {
                let service = candidate.services[index]
                guard let scpdURL = candidate.url(service.scpdURL),
                      let (scpd, _) = try? await URLSession.shared.data(for: URLRequest(url: scpdURL, timeoutInterval: 5))
                else { continue }
                candidate.services[index].actions = XMLLeaves.parse(scpd).actionNames
                Log.shared.save("scpd-\(tag)-\(service.shortName).xml", scpd)
            }
            return candidate
        } catch {
            say("  \(address) \(location): \(error.localizedDescription)")
            return nil
        }
    }

    private func listDevices() {
        if devices.isEmpty {
            say("no renderers found")
            return
        }
        for (index, candidate) in devices.enumerated() {
            let marker = candidate.udn == device?.udn ? "*" : " "
            say("\(marker) \(index + 1). \(candidate.summary)")
        }
    }

    private func select(_ candidate: UPnPDevice) {
        device = candidate
        localIP = localAddress(toward: candidate.address) ?? localIP
        Self.stopRequest = try? SOAP.request(candidate, "AVTransport", "Stop", [("InstanceID", "0")])
        say("using \(candidate.friendlyName) — the Mac serves files from http://\(localIP):\(server.port)")
        for service in candidate.services {
            say("  \(service.shortName): \(service.actions.joined(separator: ", "))")
        }
    }

    private func requireDevice() throws -> UPnPDevice {
        guard let device else { throw ToolError("no renderer selected — discover, then use <n>") }
        return device
    }

    // MARK: - SOAP

    @discardableResult
    private func soap(_ service: String, _ action: String, _ args: [(String, String)] = [],
                      quiet: Bool = false) async throws -> [String: String] {
        let device = try requireDevice()
        if !quiet {
            say("soap → \(service).\(action) " + args.map { "\($0.0)=\(Self.short($0.1))" }.joined(separator: " "))
        }
        let started = Date()
        do {
            let result = try await SOAP.call(device, service, action, args)
            if !quiet {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                say("soap ← \(action) \(ms) ms " + result.sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(Self.short($0.value))" }.joined(separator: " "))
            }
            return result
        } catch {
            if !quiet { say("soap ✗ \(action): \(error)") }
            throw error
        }
    }

    @discardableResult
    private func avt(_ action: String, _ args: [(String, String)] = [], quiet: Bool = false) async throws -> [String: String] {
        try await soap("AVTransport", action, [("InstanceID", "0")] + args, quiet: quiet)
    }

    @discardableResult
    private func rc(_ action: String, _ args: [(String, String)] = [], quiet: Bool = false) async throws -> [String: String] {
        try await soap("RenderingControl", action, [("InstanceID", "0")] + args, quiet: quiet)
    }

    private func snapshot(quiet: Bool = true) async throws -> Snapshot {
        let transport = try await avt("GetTransportInfo", quiet: quiet)
        let position = try await avt("GetPositionInfo", quiet: quiet)
        return Snapshot(state: transport["CurrentTransportState"] ?? "?",
                        status: transport["CurrentTransportStatus"] ?? "?",
                        relText: position["RelTime"] ?? "?",
                        durationText: position["TrackDuration"] ?? "?",
                        uri: position["TrackURI"] ?? "",
                        track: position["Track"] ?? "?")
    }

    private func waitFor(timeout: Double, _ condition: (Snapshot) -> Bool) async -> Snapshot? {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if let snapshot = try? await snapshot(), condition(snapshot) { return snapshot }
            await sleep(0.25)
        }
        return nil
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Actions

    private func info() async throws {
        let device = try requireDevice()
        say("device: \(device.summary)\n  UDN \(device.udn)\n  description \(device.location)")
        note("Device: \(device.summary) · \(device.udn)")
        if device.service("ConnectionManager") != nil, let result = try? await soap("ConnectionManager", "GetProtocolInfo") {
            let sink = (result["Sink"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            Log.shared.save("protocolinfo-sink.txt", Data(sink.joined(separator: "\n").utf8))
            let types = Set(sink.compactMap { entry -> String? in
                let parts = entry.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
                return parts.count >= 3 ? String(parts[2]) : nil
            }).sorted()
            note("Accepts (protocolInfo sink, \(sink.count) entries): " + types.joined(separator: ", "))
        }
        for action in ["GetTransportInfo", "GetMediaInfo", "GetPositionInfo", "GetTransportSettings",
                       "GetDeviceCapabilities", "GetCurrentTransportActions"] {
            _ = try? await avt(action)
        }
        _ = try? await rc("GetVolume", [("Channel", "Master")])
        _ = try? await rc("GetVolumeDB", [("Channel", "Master")])
        _ = try? await rc("GetVolumeDBRange", [("Channel", "Master")])
        _ = try? await rc("GetMute", [("Channel", "Master")])
        say("SetNextAVTransportURI listed in the AVTransport SCPD: \(Self.supportsNext(device) ? "yes" : "no")")
    }

    private struct Registered {
        let path: String
        let url: String
        let mime: String
        let metadata: String
        let info: FileInfo
        var name: String { URL(string: url)?.lastPathComponent ?? url }
    }

    private func register(_ path: String) throws -> Registered {
        let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.isReadableFile(atPath: file.path) else { throw ToolError("cannot read \(file.path)") }
        let route = server.register(file)
        let url = "http://\(localIP):\(server.port)\(route.path)"
        let info = FileInfo(file)
        say("serving \(file.lastPathComponent) at \(url) [\(route.mime)] \(info.label)")
        let metadata = sendMetadata
            ? didl(title: file.deletingPathExtension().lastPathComponent, url: url, mime: route.mime, info: info) : ""
        return Registered(path: route.path, url: url, mime: route.mime, metadata: metadata, info: info)
    }

    @discardableResult
    private func play(_ path: String) async throws -> Registered {
        let item = try register(path)
        try await avt("SetAVTransportURI", [("CurrentURI", item.url), ("CurrentURIMetaData", item.metadata)])
        try await avt("Play", [("Speed", "1")])
        return item
    }

    @discardableResult
    private func setNext(_ path: String) async throws -> Registered {
        let item = try register(path)
        try await avt("SetNextAVTransportURI", [("NextURI", item.url), ("NextURIMetaData", item.metadata)])
        return item
    }

    private func seek(_ seconds: Double) async throws {
        try await avt("Seek", [("Unit", "REL_TIME"), ("Target", hms(seconds))])
    }

    private func volume(quiet: Bool = false) async throws -> Int {
        let result = try await rc("GetVolume", [("Channel", "Master")], quiet: quiet)
        guard let value = Int(result["CurrentVolume"] ?? "") else { throw ToolError("no CurrentVolume in answer") }
        return value
    }

    /// Never jumps up by surprise — a Devialet at 100 is not a test result anyone wants.
    private func setVolume(_ level: Int, force: Bool) async throws {
        let current = try await volume()
        if level > current + 5, !force {
            throw ToolError("refusing \(current) → \(level) (more than +5); use vol! \(level) if you mean it")
        }
        try await rc("SetVolume", [("Channel", "Master"), ("DesiredVolume", String(level))])
    }

    private func startWatch() {
        watchTask?.cancel()
        say("watch on (changes, plus position every 10 s)")
        watchTask = Task { [weak self] in
            var last = ""
            var lastLogged = Date.distantPast
            while !Task.isCancelled {
                guard let self else { return }
                if let snapshot = try? await self.snapshot() {
                    let key = "\(snapshot.state) \(snapshot.uri) \(snapshot.track) \(snapshot.status)"
                    if key != last || Date().timeIntervalSince(lastLogged) > 10 {
                        say("watch: \(snapshot)")
                        last = key
                        lastLogged = Date()
                    }
                }
                await self.sleep(1)
            }
        }
    }

    private func subscribe() async {
        guard let device else { return }
        for name in ["AVTransport", "RenderingControl"] {
            guard let service = device.service(name), let url = device.url(service.eventSubURL) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "SUBSCRIBE"
            request.setValue("<http://\(localIP):\(server.port)/evt/\(name)>", forHTTPHeaderField: "CALLBACK")
            request.setValue("upnp:event", forHTTPHeaderField: "NT")
            request.setValue("Second-1800", forHTTPHeaderField: "TIMEOUT")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let sid = http?.value(forHTTPHeaderField: "SID")
                say("gena: SUBSCRIBE \(name) → HTTP \(http?.statusCode ?? 0) SID=\(sid ?? "-") "
                    + "TIMEOUT=\(http?.value(forHTTPHeaderField: "TIMEOUT") ?? "-")")
                if let sid, http?.statusCode == 200 {
                    subscriptions.append((url, sid))
                } else {
                    note("GENA SUBSCRIBE \(name): HTTP \(http?.statusCode ?? 0)")
                }
            } catch {
                note("GENA SUBSCRIBE \(name) failed: \(error.localizedDescription)")
            }
        }
    }

    private func unsubscribe() async {
        for (url, sid) in subscriptions {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "UNSUBSCRIBE"
            request.setValue(sid, forHTTPHeaderField: "SID")
            _ = try? await URLSession.shared.data(for: request)
        }
        subscriptions.removeAll()
    }

    // MARK: - Scripted tests

    private func formats(_ folder: String) async throws {
        let directory = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
        let audio: Set<String> = ["flac", "wav", "aif", "aiff", "m4a", "mp3", "dsf", "dff", "ogg"]
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { audio.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw ToolError("no audio files in \(directory.path)") }
        say("formats: \(files.count) files, about 10 s each — listen as well")

        var rows: [String] = []
        for file in files {
            say("──── \(file.lastPathComponent)")
            _ = try? await avt("Stop", quiet: true)
            await sleep(1)
            let started = Date()
            var result = "no PLAYING within 12 s"
            var last: Snapshot?
            var item: Registered?
            do {
                item = try await play(file.path)
                var playingSince: Date?
                while Date().timeIntervalSince(started) < 12 {
                    if let snapshot = try? await snapshot() {
                        last = snapshot
                        if snapshot.state == "PLAYING" {
                            let since = playingSince ?? Date()
                            playingSince = since
                            if (snapshot.rel ?? 0) >= 2 || Date().timeIntervalSince(since) >= 4 {
                                result = String(format: "OK, playing after %.1f s", since.timeIntervalSince(started))
                                break
                            }
                        } else if snapshot.state == "STOPPED" || snapshot.state == "NO_MEDIA_PRESENT",
                                  Date().timeIntervalSince(started) > 4 {
                            result = "\(snapshot.state) (status \(snapshot.status))"
                            break
                        }
                    }
                    await sleep(0.3)
                }
                if result.hasPrefix("OK") { await sleep(3) }
            } catch {
                result = "ERROR \(error)"
            }
            let requested = item.map { server.hits($0.path) } ?? 0
            let row = "\(file.lastPathComponent) | \(item?.info.label ?? "-") | \(item?.mime ?? "-") | \(result) "
                + "| requested \(requested)× | \(last?.description ?? "-")"
            say("formats: \(row)")
            rows.append(row)
            if guided { tell("   \(result.hasPrefix("OK") ? "✓" : "✗") \(file.deletingPathExtension().lastPathComponent)") }
        }
        _ = try? await avt("Stop")
        let table = "file | format | mime | result | requested | last state\n" + rows.joined(separator: "\n")
        Log.shared.save("formats.txt", Data(table.utf8))
        note("Formats:\n  " + rows.joined(separator: "\n  "))
        if !guided { say("FORMAT RESULTS\n" + table) }
    }

    /// Play, pause / resume, seek, volume, SetNext and the end of a track.
    @discardableResult
    private func auto(_ first: String, _ second: String?) async throws -> PlayOutcome {
        let device = try requireDevice()
        defer { if !guided { say("SUMMARY\n" + results.joined(separator: "\n")) } }
        try await info()
        note("SetNextAVTransportURI in the SCPD: \(Self.supportsNext(device) ? "yes" : "no")")
        if subscriptions.isEmpty { await subscribe() }

        // 1. Play
        _ = try? await avt("Stop", quiet: true)
        let started = Date()
        let a: Registered
        do {
            a = try await play(first)
        } catch {
            note("Play: refused — \(error)")
            return .refused
        }
        guard await waitFor(timeout: 15, { $0.state == "PLAYING" }) != nil else {
            let now = (try? await snapshot())?.description ?? "?"
            let hits = server.hits(a.path)
            note("Play: no PLAYING within 15 s — file requested \(hits)×, now \(now)")
            _ = try? await avt("Stop", quiet: true)
            return hits > 0 ? .fetchedButSilent : .neverFetched
        }
        note(String(format: "Play: PLAYING after %.1f s, file requested %d×", Date().timeIntervalSince(started), server.hits(a.path)))
        await sleep(6)

        // 2. Pause / resume
        do {
            try await avt("Pause")
            let paused = await waitFor(timeout: 5) { $0.state == "PAUSED_PLAYBACK" }
            note("Pause: \(paused != nil ? "PAUSED_PLAYBACK" : "did not reach PAUSED_PLAYBACK")")
            await sleep(3)
            let resumeStarted = Date()
            try await avt("Play", [("Speed", "1")])
            let resumed = await waitFor(timeout: 8) { $0.state == "PLAYING" }
            note(resumed != nil ? String(format: "Resume: PLAYING after %.1f s", Date().timeIntervalSince(resumeStarted))
                                : "Resume: no PLAYING")
        } catch {
            note("Pause / resume: \(error)")
        }
        await sleep(4)

        // 3. Seek
        let duration = (try? await snapshot())?.duration ?? a.info.duration ?? 0
        note("Duration: renderer \(hms(duration)), file \(a.info.duration.map(hms) ?? "?")")
        if duration > 60 {
            do {
                let seekStarted = Date()
                try await seek(30)
                if let landed = await waitFor(timeout: 10, { $0.state == "PLAYING" && abs(($0.rel ?? -100) - 30) < 5 }) {
                    note(String(format: "Seek to 0:30: playing at %@ after %.1f s", landed.relText,
                                Date().timeIntervalSince(seekStarted)))
                } else {
                    let now = (try? await snapshot())?.description ?? "?"
                    note("Seek to 0:30: did not land — \(now)")
                }
            } catch {
                note("Seek: \(error)")
            }
            await sleep(4)
        } else {
            note("Seek: skipped, track shorter than 60 s")
        }

        // 4. Volume — only ever down a little, then back.
        if let level = try? await volume() {
            note("Volume: \(level)")
            if level >= 3 {
                _ = try? await setVolume(level - 3, force: false)
                let readBack = try? await volume()
                note("SetVolume \(level - 3) → reads \(readBack.map(String.init) ?? "?")")
                _ = try? await setVolume(level, force: false)
            }
        } else {
            note("GetVolume failed")
        }

        // 5. End of track, with or without a next track.
        var b: Registered?
        if let second {
            do {
                b = try await setNext(second)
                note("SetNextAVTransportURI: accepted")
            } catch {
                note("SetNextAVTransportURI: refused — \(error)")
            }
        }
        guard duration > 20 else {
            note("End of track: skipped, duration unknown or under 20 s")
            _ = try? await avt("Stop")
            return .played
        }
        do {
            try await seek(duration - 10)
        } catch {
            note("End of track: seek refused — \(error)")
            _ = try? await avt("Stop")
            return .played
        }
        say("end test: watching the last 10 s and what follows (25 s)")
        var transitions: [String] = []
        var last = ""
        let endStarted = Date()
        while Date().timeIntervalSince(endStarted) < 25 {
            if let snapshot = try? await snapshot() {
                let key = "\(snapshot.state) uri=\(snapshot.uriName) track=\(snapshot.track)"
                if key != last {
                    let line = String(format: "+%.2f s ", Date().timeIntervalSince(endStarted)) + "\(key) rel=\(snapshot.relText)"
                    say("end test: \(line)")
                    transitions.append(line)
                    last = key
                }
            }
            await sleep(0.25)
        }
        note("End of track:\n  " + transitions.joined(separator: "\n  "))
        if let b {
            if let switchIndex = transitions.firstIndex(where: { $0.contains("uri=\(b.name)") }) {
                let stopped = transitions[..<switchIndex].contains { $0.contains(" STOPPED ") || $0.contains("NO_MEDIA") }
                note(stopped ? "Next track: switched, with STOPPED in between" : "Next track: switched without STOPPED")
            } else {
                note("Next track: did not switch to \(b.name)")
            }
        }
        _ = try? await avt("Stop")
        return .played
    }

    // MARK: - Helpers

    /// One line from stdin on a thread of its own, so the main actor stays free meanwhile.
    nonisolated private static func readLineAsync() async -> String? {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: readLine()) }
        }
    }

    /// Splits like a shell: quotes and backslash escapes, so dragged-in Finder paths work.
    static func tokens(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var started = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
                started = true
            } else if character == "\\", quote != "'" {
                escaped = true
            } else if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character == " " || character == "\t" {
                if started || !current.isEmpty { tokens.append(current) }
                current = ""
                started = false
            } else {
                current.append(character)
                started = true
            }
        }
        if started || !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func isDevialet(_ device: UPnPDevice) -> Bool {
        [device.manufacturer, device.friendlyName, device.modelName].contains { $0.localizedCaseInsensitiveContains("devialet") }
    }

    static func supportsNext(_ device: UPnPDevice) -> Bool {
        device.service("AVTransport")?.actions.contains("SetNextAVTransportURI") == true
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }

    static func short(_ value: String) -> String {
        let flat = value.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 160 ? String(flat.prefix(160)) + "…(\(flat.count))" : flat
    }

    static func fileSafe(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}
