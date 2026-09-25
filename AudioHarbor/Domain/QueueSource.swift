import Foundation

/// Where the play queue came from, shown in the Deck's context rail.
enum QueueSource: Hashable, Sendable {
    case album(String)
    case artist(String)
    case folder(String)
    case playlist(String)
    case label(String)

    var name: String {
        switch self {
        case .album(let name), .artist(let name), .folder(let name), .playlist(let name), .label(let name):
            name
        }
    }

    var kindLabel: String {
        switch self {
        case .album: "Album"
        case .artist: "Artist"
        case .folder: "Folder"
        case .playlist: "Playlist"
        case .label: "Label"
        }
    }
}
