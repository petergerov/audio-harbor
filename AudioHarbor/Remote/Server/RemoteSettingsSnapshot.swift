import Foundation

/// Builds and applies Mac Settings for the remote protocol.
@MainActor
enum RemoteSettingsSnapshot {
    static func make(from appModel: AppModel) -> SettingsSnapshot {
        let playback = appModel.playback
        let status = playback.outputStatus
        let devices = status.devices.map { device in
            RemoteOutputDeviceDTO(
                uid: device.uid,
                name: device.name,
                kind: device.kind == .network ? "network" : "local",
                supportsExclusive: device.supportsExclusive,
                supportsDoP: device.supportsDoP
            )
        }
        let picked = playback.outputDeviceUID.flatMap { uid in
            status.devices.first { $0.uid == uid }
        }
        let canExclusive = picked?.supportsExclusive ?? status.canExclusive
        let canDoP = picked?.supportsDoP ?? status.canDoP

        let output = RemoteOutputSettingsDTO(
            devices: devices,
            selectedUID: playback.outputDeviceUID,
            selectedName: playback.outputDeviceName ?? picked?.name ?? status.activeDevice?.name,
            isNetworkSelected: playback.isNetworkOutputSelected,
            isDeviceMissing: playback.isOutputDeviceMissing,
            outputMode: playback.outputMode.rawValue,
            effectiveOutputMode: playback.effectiveOutputMode.rawValue,
            canExclusive: canExclusive,
            canDoP: canDoP,
            networkChoice: playback.networkOutputChoice.rawValue,
            supportsNativeDSD: playback.networkPlayerFormats?.supportsNativeDSD == true,
            dsdPCMLevel: playback.dsdPCMLevel.rawValue
        )

        #if os(macOS)
        let sharing = RemoteSharingSettingsDTO(
            enabled: appModel.sharing.isEnabled,
            statusText: appModel.sharing.statusText,
            blockedByLicense: appModel.sharing.isBlockedByLicense,
            activeStreams: appModel.sharing.activeStreams
        )
        #else
        let sharing = RemoteSharingSettingsDTO(
            enabled: false,
            statusText: "Sharing is Mac-only",
            blockedByLicense: false,
            activeStreams: 0
        )
        #endif

        let directories = appModel.library.folders.map {
            RemoteDirectoryDTO(id: $0.id, name: $0.name, displayPath: $0.displayPath)
        }

        let about = RemoteAboutDTO(
            appName: Brand.name,
            versionLabel: Brand.versionLabel,
            tagline: Brand.tagline,
            licenseHeadline: appModel.license.statusHeadline,
            licenseDetail: appModel.license.statusDetail
        )

        return SettingsSnapshot(
            output: output,
            sharing: sharing,
            directories: directories,
            isScanning: appModel.library.isScanning,
            about: about
        )
    }

    /// Applies a remote patch. Returns nil on success, or an error message.
    static func apply(_ patch: SettingsPatch, to appModel: AppModel) -> String? {
        let playback = appModel.playback
        switch patch {
        case .outputDevice(let uid):
            let cleaned = uid?.trimmingCharacters(in: .whitespacesAndNewlines)
            let next = (cleaned?.isEmpty == false) ? cleaned : nil
            if let next, !playback.outputStatus.devices.contains(where: { $0.uid == next }) {
                // Allow a remembered network pick that is offline right now.
                if !next.hasPrefix("upnp:") {
                    return "That output is not available"
                }
            }
            playback.outputDeviceUID = next
            return nil

        case .outputMode(let raw):
            guard let mode = OutputMode(rawValue: raw) else {
                return "Unknown output mode"
            }
            if mode != .shared, !playback.isAvailable(mode) {
                return "\(mode.title) needs a capable USB DAC"
            }
            playback.outputMode = mode
            return nil

        case .networkChoice(let raw):
            guard let choice = NetworkOutputChoice(rawValue: raw) else {
                return "Unknown network mode"
            }
            if choice == .dsd, playback.networkPlayerFormats?.supportsNativeDSD != true {
                return "This player does not list DSD"
            }
            guard playback.isNetworkOutputSelected else {
                return "Pick a network player first"
            }
            playback.networkOutputChoice = choice
            return nil

        case .dsdPCMLevel(let raw):
            guard let level = DSDPCMLevel(rawValue: raw) else {
                return "Unknown DSD level"
            }
            playback.dsdPCMLevel = level
            return nil

        case .sharingEnabled(let on):
            #if os(macOS)
            appModel.sharing.setEnabled(on)
            return nil
            #else
            _ = on
            return "Sharing is Mac-only"
            #endif

        case .rebuildIndex:
            if appModel.library.isScanning {
                return "Catalogue is already rebuilding"
            }
            if appModel.library.folders.isEmpty {
                return "No directories connected"
            }
            appModel.requestIndexRebuild()
            return nil
        }
    }
}
