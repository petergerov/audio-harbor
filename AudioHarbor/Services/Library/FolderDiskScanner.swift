import Foundation

/// Reads folders straight from disk, for places the catalogue index has not reached yet
/// (demo library, mid-scan).
enum FolderDiskScanner {
    private static let audioExtensions = CatalogueIndexer.audioExtensions

    /// Subfolders that hold audio, and audio files, each sorted by name.
    static func listContents(at url: URL) -> (directories: [URL], audioFiles: [URL]) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return ([], []) }

        var directories: [URL] = []
        var files: [URL] = []

        for item in items {
            if ICloudItem.isHiddenJunk(item) { continue }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if containsAudio(item) {
                    directories.append(item)
                }
            } else if let audioURL = ICloudItem.resolvedAudioURL(from: item, extensions: audioExtensions) {
                files.append(audioURL)
            }
        }

        let byName = { (lhs: URL, rhs: URL) in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
        return (directories.sorted(by: byName), files.sorted(by: byName))
    }

    /// True if any file below `url`, at any depth, is supported audio.
    static func containsAudio(_ url: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return false }
        while let fileURL = enumerator.nextObject() as? URL {
            if ICloudItem.isHiddenJunk(fileURL) { continue }
            if ICloudItem.resolvedAudioURL(from: fileURL, extensions: audioExtensions) != nil {
                return true
            }
        }
        return false
    }
}
