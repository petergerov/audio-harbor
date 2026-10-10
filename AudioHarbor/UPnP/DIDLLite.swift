#if os(macOS)
import Foundation

/// DIDL-Lite metadata for SetAVTransportURI — one music track item.
enum DIDLLite {
    static func musicTrack(
        title: String,
        artist: String,
        album: String,
        uri: String,
        mime: String,
        duration: TimeInterval?,
        sampleRateHz: Int?,
        bitDepth: Int?,
        channels: Int?,
        artworkURL: String? = nil
    ) -> String {
        var attributes = "protocolInfo=\"http-get:*:\(mime):\(MediaHTTPServer.dlnaFeatures)\""
        if let duration, duration > 0 {
            attributes += " duration=\"\(UPnPControlPoint.formatTime(duration))\""
        }
        if let sampleRateHz { attributes += " sampleFrequency=\"\(sampleRateHz)\"" }
        if let bitDepth { attributes += " bitsPerSample=\"\(bitDepth)\"" }
        if let channels { attributes += " nrAudioChannels=\"\(channels)\"" }
        let art = artworkURL.map {
            "<upnp:albumArtURI>\(UPnPXML.escape($0))</upnp:albumArtURI>"
        } ?? ""

        return """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">\
        <item id="1" parentID="0" restricted="1">\
        <dc:title>\(UPnPXML.escape(title))</dc:title>\
        <upnp:artist>\(UPnPXML.escape(artist))</upnp:artist>\
        <upnp:album>\(UPnPXML.escape(album))</upnp:album>\
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>\
        \(art)\
        <res \(attributes)>\(UPnPXML.escape(uri))</res>\
        </item></DIDL-Lite>
        """
    }

    static func musicTrack(track: Track, uri: String, mime: String, artworkURL: String? = nil) -> String {
        musicTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            uri: uri,
            mime: mime,
            duration: track.duration > 0 ? track.duration : nil,
            sampleRateHz: track.sampleRateHz,
            bitDepth: track.bitDepth,
            channels: track.channelCount,
            artworkURL: artworkURL
        )
    }
}
#endif
