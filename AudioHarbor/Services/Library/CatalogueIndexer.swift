import Foundation

enum CatalogueIndexer {
    static let audioExtensions = Set(["flac", "m4a", "alac", "wav", "aiff", "aif", "aac", "mp3", "dsf", "dff", "iso"])

    static func enumerateAudioFiles(in roots: [URL]) -> [FileFingerprint] {
        let fm = FileManager.default
        var files: [FileFingerprint] = []
        files.reserveCapacity(2048)
        var seen = Set<String>()

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isUbiquitousItemKey
                ],
                options: [.skipsPackageDescendants]
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                if ICloudItem.isHiddenJunk(item) { continue }
                guard let audioURL = ICloudItem.resolvedAudioURL(from: item, extensions: audioExtensions) else {
                    continue
                }
                let values = try? audioURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey
                ])
                let isPlaceholder = item.pathExtension.lowercased() == "icloud"
                if values?.isRegularFile != true, !isPlaceholder { continue }
                let path = audioURL.path
                guard seen.insert(path).inserted else { continue }
                files.append(
                    FileFingerprint(
                        url: audioURL,
                        path: path,
                        fileSize: Int64(values?.fileSize ?? 0),
                        mtime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                    )
                )
            }
        }
        return files
    }

    static func plan(
        files: [FileFingerprint],
        existing: [String: StoredFingerprint],
        force: Bool
    ) -> (toRead: [FileFingerprint], toDelete: [String], staleVirtual: [String], unchanged: Int) {
        var toRead: [FileFingerprint] = []
        toRead.reserveCapacity(force ? files.count : 64)
        var live = Set<String>(minimumCapacity: files.count)
        var staleVirtual: [String] = []
        var unchanged = 0

        var childrenByParent: [String: [String]] = [:]
        for path in existing.keys {
            childrenByParent[VirtualTrackPath.filePath(from: path), default: []].append(path)
        }

        func fingerprintMatches(_ path: String, file: FileFingerprint) -> Bool {
            guard let stored = existing[path] else { return false }
            return stored.fileSize == file.fileSize && abs(stored.mtime - file.mtime) < 0.6
        }

        for file in files {
            let children = childrenByParent[file.path] ?? []
            let virtual = children.filter { VirtualTrackPath.isVirtual($0) }
            let ext = file.url.pathExtension.lowercased()
            let treatAsContainer = ext == "iso" || !virtual.isEmpty

            if treatAsContainer {
                let allMatch = !virtual.isEmpty && virtual.allSatisfy { fingerprintMatches($0, file: file) }
                if !force, allMatch {
                    virtual.forEach { live.insert($0) }
                    unchanged += virtual.count
                } else {
                    toRead.append(file)
                    staleVirtual.append(contentsOf: virtual)
                    if existing[file.path] != nil {
                        staleVirtual.append(file.path)
                    }
                }
            } else {
                live.insert(file.path)
                if force {
                    toRead.append(file)
                } else if fingerprintMatches(file.path, file: file) {
                    unchanged += 1
                } else {
                    toRead.append(file)
                }
            }
        }

        let liveFiles = Set(files.map(\.path))
        let toDelete = existing.keys.filter { key in
            let parent = VirtualTrackPath.filePath(from: key)
            return !live.contains(key) && !liveFiles.contains(parent)
        }
        return (toRead, toDelete, staleVirtual, unchanged)
    }

    static func readMetadata(
        files: [FileFingerprint],
        labelsByPath: [String: [String]],
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async -> [IndexedTrackRecord] {
        guard !files.isEmpty else { return [] }
        let chunkSize = max(4, min(8, ProcessInfo.processInfo.activeProcessorCount))
        var records: [IndexedTrackRecord] = []
        records.reserveCapacity(files.count)

        var processed = 0
        for chunk in files.chunked(into: chunkSize) {
            let batch = await withTaskGroup(of: [IndexedTrackRecord].self, returning: [IndexedTrackRecord].self) { group in
                for file in chunk {
                    group.addTask {
                        await readOne(file: file, labelsByPath: labelsByPath)
                    }
                }
                var out: [IndexedTrackRecord] = []
                out.reserveCapacity(chunk.count)
                for await records in group {
                    out.append(contentsOf: records)
                }
                return out
            }
            records.append(contentsOf: batch)
            processed += chunk.count
            await progress(processed, files.count)
        }
        return records
    }

    private static func readOne(file: FileFingerprint, labelsByPath: [String: [String]]) async -> [IndexedTrackRecord] {
        await ICloudItem.ensureDownloaded(file.url)
        let ext = file.url.pathExtension.lowercased()
        if ext == "iso" {
            return indexSACD(file: file, labelsByPath: labelsByPath)
        }
        if ext == "dff" {
            let chapters = indexDFFChapters(file: file, labelsByPath: labelsByPath)
            if chapters.count > 1 {
                return chapters
            }
        }
        return [await indexSingle(file: file, labelsByPath: labelsByPath)]
    }

    private static func indexSACD(file: FileFingerprint, labelsByPath: [String: [String]]) -> [IndexedTrackRecord] {
        guard let tracks = try? SACDISO.listTracks(url: file.url), !tracks.isEmpty else {
            return []
        }
        return tracks.map { track in
            let identity = VirtualTrackPath.sacd(file.path, track: track.number)
            return IndexedTrackRecord(
                path: identity,
                title: track.title,
                artist: track.artist,
                album: track.album,
                trackNumber: track.number,
                year: track.year,
                duration: track.duration,
                format: .sacd,
                sampleRateHz: track.sampleRateHz,
                bitDepth: 1,
                channelCount: track.channelCount,
                fileSize: file.fileSize,
                mtime: file.mtime,
                artworkHash: nil,
                filename: file.url.lastPathComponent,
                labels: labelsByPath[identity] ?? []
            )
        }
    }

    private static func indexDFFChapters(file: FileFingerprint, labelsByPath: [String: [String]]) -> [IndexedTrackRecord] {
        guard let header = try? DSDDecoder.probe(url: file.url) else { return [] }
        let chapters = DFFChapters.list(url: file.url, header: header)
        guard chapters.count > 1 else { return [] }
        let album = "Unknown Album"
        return chapters.map { chapter in
            let identity = VirtualTrackPath.dff(file.path, track: chapter.number)
            return IndexedTrackRecord(
                path: identity,
                title: chapter.title,
                artist: "Unknown Artist",
                album: album,
                trackNumber: chapter.number,
                year: nil,
                duration: chapter.duration,
                format: .dff,
                sampleRateHz: header.sampleRate,
                bitDepth: 1,
                channelCount: header.channelCount,
                fileSize: file.fileSize,
                mtime: file.mtime,
                artworkHash: nil,
                filename: file.url.lastPathComponent,
                labels: labelsByPath[identity] ?? []
            )
        }
    }

    private static func indexSingle(file: FileFingerprint, labelsByPath: [String: [String]]) async -> IndexedTrackRecord {
        let meta = await MetadataReader.read(url: file.url)
        let artworkHash = meta.artworkData.flatMap { ArtworkCache.shared.store($0) }
        return IndexedTrackRecord(
            path: file.path,
            title: meta.title,
            artist: meta.artist,
            album: meta.album,
            trackNumber: meta.trackNumber,
            year: meta.year,
            duration: meta.duration,
            format: meta.format,
            sampleRateHz: meta.sampleRateHz,
            bitDepth: meta.bitDepth,
            channelCount: meta.channelCount,
            fileSize: file.fileSize,
            mtime: file.mtime,
            artworkHash: artworkHash,
            filename: file.url.lastPathComponent,
            labels: labelsByPath[file.path] ?? []
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<next]))
            index = next
        }
        return chunks
    }
}
