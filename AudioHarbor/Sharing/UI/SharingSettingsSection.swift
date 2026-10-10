#if os(macOS)
import SwiftUI

/// Settings → Sharing: the library as a music server for players on the home network.
struct SharingSettingsSection: View {
    @Bindable var sharing: MusicServerService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Players on your network — such as mconnect on an iPhone — browse your library and play the files themselves. They get the files as they are; nothing is converted.")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(
                get: { sharing.isEnabled },
                set: { sharing.setEnabled($0) }
            )) {
                Text("Share Library on the Network")
                    .font(HarborFont.title(14))
                    .foregroundStyle(HarborColor.ivory)
            }
            .toggleStyle(.switch)
            .tint(HarborColor.amber)

            Text(sharing.statusText)
                .font(HarborFont.mono(11))
                .foregroundStyle(HarborColor.ivoryDim)

            if sharing.isBlockedByLicense {
                Text("The trial has ended — players can browse, but not play, until Audio Harbor is unlocked.")
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.amber)
            } else if sharing.activeStreams > 0 {
                Text(sharing.activeStreams == 1 ? "Streaming to a player" : "\(sharing.activeStreams) streams to players")
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.amber)
            }

            Text("Anyone on this network can browse and play the library while sharing is on — DLNA has no sign-in. SACD ISO tracks are extracted before they play; DFF files with chapters are not shared.")
                .font(HarborFont.body(12))
                .foregroundStyle(HarborColor.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
