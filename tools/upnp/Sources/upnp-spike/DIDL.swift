import Foundation
import UPnPCommon

/// The metadata sent with SetAVTransportURI: one item, the file's own format in its `<res>`.
func didl(title: String, url: String, mime: String, info: FileInfo) -> String {
    "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" "
        + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">"
        + "<item id=\"1\" parentID=\"0\" restricted=\"1\"><dc:title>\(xmlEscape(title))</dc:title>"
        + "<upnp:artist>Audio Harbor spike</upnp:artist><upnp:album>UPnP test</upnp:album>"
        + "<upnp:class>object.item.audioItem.musicTrack</upnp:class>"
        + "<res \(info.resAttributes(mime: mime, features: MediaServer.dlnaFeatures))>\(xmlEscape(url))</res></item></DIDL-Lite>"
}
