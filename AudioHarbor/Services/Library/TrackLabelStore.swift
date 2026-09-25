import Foundation

/// User labels keyed by catalogue path, so they survive track ID churn on rescan.
/// Every change is written to UserDefaults straight away.
struct TrackLabelStore {
    private(set) var labelsByPath: [String: [String]] = [:]
    private let defaultsKey = DefaultsKey.trackLabels

    init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }
        labelsByPath = decoded
    }

    func labels(forPath path: String) -> [String] {
        labelsByPath[path] ?? []
    }

    /// Returns `false` when nothing changed: the label is blank or the track already has it.
    mutating func add(_ label: String, to track: Track) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var current = labelsByPath[track.cataloguePath] ?? track.labels
        guard !current.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return false }
        current.append(trimmed)
        labelsByPath[track.cataloguePath] = current.sorted(by: Self.alphabetical)
        save()
        return true
    }

    mutating func remove(_ label: String, from track: Track) {
        var current = labelsByPath[track.cataloguePath] ?? track.labels
        current.removeAll { $0.caseInsensitiveCompare(label) == .orderedSame }
        store(current, for: track.cataloguePath)
    }

    mutating func set(_ labels: [String], for track: Track) {
        let trimmed = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        store(Array(Set(trimmed)).sorted(by: Self.alphabetical), for: track.cataloguePath)
    }

    private mutating func store(_ labels: [String], for path: String) {
        labelsByPath[path] = labels.isEmpty ? nil : labels
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(labelsByPath) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func alphabetical(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}
