import Foundation

/// Reads folders straight from disk, for places the catalogue index has not reached yet
/// (demo library, mid-scan).
enum FolderDiskScanner {
    private static let audioExtensions = CatalogueIndexer.audioExtensions

    /// Subfolders that hold audio, then audio files, each sorted by name.
    static func listContents(at url: URL) -> [FolderBrowseEntry] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var directories: [FolderBrowseEntry] = []
        var files: [FolderBrowseEntry] = []

        for item in items {
            if ICloudItem.isHiddenJunk(item) { continue }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if containsAudio(item) {
                    directories.append(FolderBrowseEntry(name: item.lastPathComponent, url: item, kind: .directory))
                }
            } else if let audioURL = ICloudItem.resolvedAudioURL(from: item, extensions: audioExtensions) {
                files.append(FolderBrowseEntry(name: audioURL.lastPathComponent, url: audioURL, kind: .audioFile))
            }
        }

        directories.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return directories + files
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
