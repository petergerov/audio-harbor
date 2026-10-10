#if os(macOS)
import Foundation

/// The part of the library the music server shows: the views the remote browses too.
@MainActor
protocol SharedCatalogue: AnyObject {
    var albums: [Album] { get }
    var artists: [LibraryFacet] { get }
    var labels: [LibraryFacet] { get }
    var playlists: [(id: UUID, name: String)] { get }
    var folderRoots: [(id: UUID, name: String)] { get }
    /// Changes when the catalogue does, so players can drop what they cached.
    var revision: Int { get }

    func tracks(forArtist name: String) -> [Track]
    func tracks(forLabel name: String) -> [Track]
    func tracks(inPlaylist id: UUID) -> [Track]?
    func folderListing(rootID: UUID, components: [String]) -> [FolderBrowseEntry]?
    func track(forCataloguePath path: String) -> Track?
    /// A file inside a connected directory — for listing entries the index does not have yet.
    func isInConnectedFolder(_ url: URL) -> Bool
}
#endif
