import Foundation

/// Shown until the first directory is connected.
enum DemoLibrary {
    static var tracks: [Track] {
        [
            Track(
                title: "Amber Signal",
                artist: "North Room",
                album: "Quiet Hours",
                trackNumber: 1,
                year: 2024,
                duration: 243,
                format: .flac,
                sampleRateHz: 96000,
                bitDepth: 24,
                url: URL(fileURLWithPath: "/demo/quiet-hours/01-amber-signal.flac")
            ),
            Track(
                title: "Glass Corridor",
                artist: "North Room",
                album: "Quiet Hours",
                trackNumber: 2,
                year: 2024,
                duration: 318,
                format: .flac,
                sampleRateHz: 96000,
                bitDepth: 24,
                url: URL(fileURLWithPath: "/demo/quiet-hours/02-glass-corridor.flac")
            ),
            Track(
                title: "Night Wire",
                artist: "Field Tape",
                album: "DSD Sampler",
                trackNumber: 1,
                year: 2023,
                duration: 401,
                format: .dsf,
                sampleRateHz: 2_822_400,
                bitDepth: 1,
                url: URL(fileURLWithPath: "/demo/dsd/night-wire.dsf")
            ),
            Track(
                title: "Harbor Light",
                artist: "Field Tape",
                album: "Analog Sketches",
                trackNumber: 3,
                year: 2022,
                duration: 276,
                format: .alac,
                sampleRateHz: 48000,
                bitDepth: 24,
                url: URL(fileURLWithPath: "/demo/analog/harbor-light.m4a")
            ),
        ]
    }
}
