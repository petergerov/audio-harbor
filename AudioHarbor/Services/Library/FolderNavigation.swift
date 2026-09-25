import Foundation

/// Where the Directories tab is: a connected root (`nil` = the root picker) and the path below it.
struct FolderNavigation: Equatable {
    private(set) var rootID: UUID?
    /// Relative path components under the selected root.
    private(set) var pathComponents: [String] = []

    mutating func open(root id: UUID) {
        show([], in: id)
    }

    mutating func show(_ components: [String], in root: UUID) {
        rootID = root
        pathComponents = components
    }

    mutating func enter(_ directoryName: String) {
        pathComponents.append(directoryName)
    }

    /// One folder up; from the top of a root, back to the root picker.
    mutating func goUp() {
        if pathComponents.isEmpty {
            rootID = nil
        } else {
            pathComponents.removeLast()
        }
    }

    /// Jump to a breadcrumb segment: `0` = the root, `n` = the first `n` path components.
    mutating func jump(toDepth depth: Int) {
        let clamped = max(0, min(depth, pathComponents.count))
        pathComponents = Array(pathComponents.prefix(clamped))
    }

    mutating func reset() {
        rootID = nil
        pathComponents = []
    }
}
