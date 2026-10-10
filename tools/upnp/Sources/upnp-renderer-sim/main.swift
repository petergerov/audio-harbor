import Foundation
import UPnPCommon

let profile: Profile
do {
    profile = try Profile.parse(CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}

Task { @MainActor in
    let renderer = Renderer(profile: profile)
    do {
        try renderer.start()
    } catch {
        say("failed to start: \(error)")
        exit(1)
    }
    await renderer.console()
    renderer.shutdown()
    exit(0)
}
dispatchMain()
