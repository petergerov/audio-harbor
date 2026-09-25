import Foundation

/// In-memory inverted index for instant catalogue search (AND of prefix tokens).
struct CatalogueSearchIndex: Sendable {
    private var postings: [String: Set<Int>] = [:]

    mutating func rebuild(from tracks: [Track]) {
        postings.removeAll(keepingCapacity: true)
        for (index, track) in tracks.enumerated() {
            var tokens = Set<String>()
            for field in [track.title, track.artist, track.album, track.url.lastPathComponent] {
                tokens.formUnion(Self.tokenize(field))
            }
            for label in track.labels {
                tokens.formUnion(Self.tokenize(label))
            }
            for token in tokens {
                postings[token, default: []].insert(index)
            }
        }
    }

    func matchingIndices(query: String, trackCount: Int) -> Set<Int>? {
        let tokens = Self.tokenize(query)
        guard !tokens.isEmpty else { return nil }

        var result: Set<Int>?
        for token in tokens {
            var union = Set<Int>()
            if token.count >= 3 {
                for (key, ids) in postings where key.hasPrefix(token) {
                    union.formUnion(ids)
                }
            } else if let exact = postings[token] {
                union = exact
            } else {
                for (key, ids) in postings where key.hasPrefix(token) {
                    union.formUnion(ids)
                    if union.count == trackCount { break }
                }
            }
            if let current = result {
                result = current.intersection(union)
            } else {
                result = union
            }
            if result?.isEmpty == true { break }
        }
        return result
    }

    static func tokenize(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
