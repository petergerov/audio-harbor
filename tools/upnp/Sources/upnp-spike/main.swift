import Foundation
import UPnPCommon

/// No arguments: the guided test for the person next to the renderer. `-i`: the command prompt.
struct Options {
    var port: UInt16 = 8642
    var interactive = false
    var descriptionURL: String?
    var makeTestFiles: String?
    var reveal = true

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 1
        while index < arguments.count {
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch arguments[index] {
            case "-i", "--interactive":
                options.interactive = true
            case "--port":
                guard let value, let port = UInt16(value) else { fail("--port <number>") }
                options.port = port
                index += 1
            case "--url":
                guard let value else { fail("--url <description URL>") }
                options.descriptionURL = value
                index += 1
            case "--make-test-files":
                guard let value else { fail("--make-test-files <folder>") }
                options.makeTestFiles = value
                index += 1
            case "--no-reveal":
                options.reveal = false
            case "-h", "--help":
                print(usage)
                exit(0)
            default:
                fail("unknown option \(arguments[index])")
            }
            index += 1
        }
        return options
    }

    static func fail(_ message: String) -> Never {
        print("\(message)\n\n\(usage)")
        exit(2)
    }

    static let usage = """
    upnp-spike [options]
      (no options)              guided test: finds the Devialet, runs every step, zips the results
      -i, --interactive         command prompt (auto, formats, play, seek, vol, watch …)
      --url <description URL>   skip SSDP and use the renderer at this URL
      --port <n>                HTTP port the renderer fetches from (default 8642, else any free one)
      --make-test-files <dir>   write the test tones to a folder and exit
      --no-reveal               do not show the result zip in the Finder (scripted runs)
    """
}

let options = Options.parse(CommandLine.arguments)

if let folder = options.makeTestFiles {
    do {
        let set = try TestFiles.make(in: URL(fileURLWithPath: (folder as NSString).expandingTildeInPath))
        print("wrote \(set.directory.path)")
        for skipped in set.skipped { print("skipped \(skipped)") }
        exit(0)
    } catch {
        print("failed: \(error)")
        exit(1)
    }
}

if !options.interactive {
    // The terminal belongs to the person running the test; the details go to the log, which
    // lands next to the program so the zip is easy to find.
    Log.echo = false
    Log.folderPrefix = "Ergebnis"
    Log.baseDirectory = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
}

Task { @MainActor in
    do {
        Spike.revealsResults = options.reveal
        let spike = try Spike(port: options.port)
        if options.interactive {
            await spike.runInteractive()
        } else {
            await spike.runGuided(descriptionURL: options.descriptionURL)
        }
        exit(0)
    } catch {
        tell("Start fehlgeschlagen: \(error)")
        exit(1)
    }
}
dispatchMain()
