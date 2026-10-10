import Foundation
import UPnPCommon

enum RendererTypes {
    static let device = "urn:schemas-upnp-org:device:MediaRenderer:1"
    static let services = [
        "urn:schemas-upnp-org:service:AVTransport:1",
        "urn:schemas-upnp-org:service:RenderingControl:1",
        "urn:schemas-upnp-org:service:ConnectionManager:1",
    ]
}

/// Device description and SCPDs, generated from one action table so they cannot disagree with
/// what `Renderer` actually answers.
enum Documents {
    static func description(_ profile: Profile) -> String {
        let services = RendererTypes.services.map { type -> String in
            let name = serviceShortName(type)
            return "<service><serviceType>\(type)</serviceType><serviceId>urn:upnp-org:serviceId:\(name)</serviceId>"
                + "<SCPDURL>/scpd/\(name).xml</SCPDURL><controlURL>/ctl/\(name)</controlURL>"
                + "<eventSubURL>/evt/\(name)</eventSubURL></service>"
        }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:dlna="urn:schemas-dlna-org:device-1-0">
        <specVersion><major>1</major><minor>0</minor></specVersion>
        <device>
        <deviceType>\(RendererTypes.device)</deviceType>
        <friendlyName>\(xmlEscape(profile.name))</friendlyName>
        <manufacturer>\(xmlEscape(profile.manufacturer))</manufacturer>
        <modelName>\(xmlEscape(profile.modelName))</modelName>
        <modelNumber>sim-0.1</modelNumber>
        <UDN>\(profile.uuid)</UDN>
        <dlna:X_DLNADOC>DMR-1.50</dlna:X_DLNADOC>
        <serviceList>\(services)</serviceList>
        </device>
        </root>
        """
    }

    // MARK: - SCPD

    /// (name, [(argument, "in"/"out", related state variable)])
    typealias Action = SOAPText.Action

    static func actions(_ service: String, _ profile: Profile) -> [Action] {
        let instance = ("InstanceID", "in", "A_ARG_TYPE_InstanceID")
        switch service {
        case "AVTransport":
            var list: [Action] = [
                ("SetAVTransportURI", [instance, ("CurrentURI", "in", "AVTransportURI"),
                                       ("CurrentURIMetaData", "in", "AVTransportURIMetaData")]),
                ("Play", [instance, ("Speed", "in", "TransportPlaySpeed")]),
                ("Pause", [instance]),
                ("Stop", [instance]),
                ("Seek", [instance, ("Unit", "in", "A_ARG_TYPE_SeekMode"), ("Target", "in", "A_ARG_TYPE_SeekTarget")]),
                ("Next", [instance]),
                ("Previous", [instance]),
                ("GetTransportInfo", [instance, ("CurrentTransportState", "out", "TransportState"),
                                      ("CurrentTransportStatus", "out", "TransportStatus"),
                                      ("CurrentSpeed", "out", "TransportPlaySpeed")]),
                ("GetPositionInfo", [instance, ("Track", "out", "CurrentTrack"), ("TrackDuration", "out", "CurrentTrackDuration"),
                                     ("TrackMetaData", "out", "CurrentTrackMetaData"), ("TrackURI", "out", "CurrentTrackURI"),
                                     ("RelTime", "out", "RelativeTimePosition"), ("AbsTime", "out", "AbsoluteTimePosition"),
                                     ("RelCount", "out", "RelativeCounterPosition"), ("AbsCount", "out", "AbsoluteCounterPosition")]),
                ("GetMediaInfo", [instance, ("NrTracks", "out", "NumberOfTracks"), ("MediaDuration", "out", "CurrentMediaDuration"),
                                  ("CurrentURI", "out", "AVTransportURI"), ("CurrentURIMetaData", "out", "AVTransportURIMetaData"),
                                  ("NextURI", "out", "NextAVTransportURI"), ("NextURIMetaData", "out", "NextAVTransportURIMetaData"),
                                  ("PlayMedium", "out", "PlaybackStorageMedium"), ("RecordMedium", "out", "RecordStorageMedium"),
                                  ("WriteStatus", "out", "RecordMediumWriteStatus")]),
                ("GetTransportSettings", [instance, ("PlayMode", "out", "CurrentPlayMode"),
                                          ("RecQualityMode", "out", "CurrentRecordQualityMode")]),
                ("GetDeviceCapabilities", [instance, ("PlayMedia", "out", "PossiblePlaybackStorageMedia"),
                                           ("RecMedia", "out", "PossibleRecordStorageMedia"),
                                           ("RecQualityModes", "out", "PossibleRecordQualityModes")]),
                ("GetCurrentTransportActions", [instance, ("Actions", "out", "CurrentTransportActions")]),
            ]
            if profile.supportsNext {
                list.insert(("SetNextAVTransportURI", [instance, ("NextURI", "in", "NextAVTransportURI"),
                                                       ("NextURIMetaData", "in", "NextAVTransportURIMetaData")]), at: 1)
            }
            return list
        case "RenderingControl":
            let channel = ("Channel", "in", "A_ARG_TYPE_Channel")
            return [
                ("GetVolume", [instance, channel, ("CurrentVolume", "out", "Volume")]),
                ("SetVolume", [instance, channel, ("DesiredVolume", "in", "Volume")]),
                ("GetMute", [instance, channel, ("CurrentMute", "out", "Mute")]),
                ("SetMute", [instance, channel, ("DesiredMute", "in", "Mute")]),
                ("GetVolumeDB", [instance, channel, ("CurrentVolume", "out", "VolumeDB")]),
                ("GetVolumeDBRange", [instance, channel, ("MinValue", "out", "VolumeDB"), ("MaxValue", "out", "VolumeDB")]),
            ]
        case "ConnectionManager":
            return [
                ("GetProtocolInfo", [("Source", "out", "SourceProtocolInfo"), ("Sink", "out", "SinkProtocolInfo")]),
                ("GetCurrentConnectionIDs", [("ConnectionIDs", "out", "CurrentConnectionIDs")]),
                ("GetCurrentConnectionInfo", [("ConnectionID", "in", "A_ARG_TYPE_ConnectionID"),
                                              ("RcsID", "out", "A_ARG_TYPE_RcsID"), ("AVTransportID", "out", "A_ARG_TYPE_AVTransportID"),
                                              ("ProtocolInfo", "out", "A_ARG_TYPE_ProtocolInfo"),
                                              ("PeerConnectionManager", "out", "A_ARG_TYPE_ConnectionManager"),
                                              ("PeerConnectionID", "out", "A_ARG_TYPE_ConnectionID"),
                                              ("Direction", "out", "A_ARG_TYPE_Direction"), ("Status", "out", "A_ARG_TYPE_ConnectionStatus")]),
            ]
        default:
            return []
        }
    }

    static func scpd(_ service: String, _ profile: Profile) -> String? {
        let list = actions(service, profile)
        guard !list.isEmpty else { return nil }
        return SOAPText.scpd(list, dataType: dataType, evented: service == "ConnectionManager" ? [] : ["LastChange"])
    }

    private static func dataType(_ variable: String) -> String {
        switch variable {
        case "A_ARG_TYPE_InstanceID", "NumberOfTracks", "CurrentTrack": "ui4"
        case "Volume": "ui2"
        case "VolumeDB", "RelativeCounterPosition", "AbsoluteCounterPosition", "A_ARG_TYPE_ConnectionID",
             "A_ARG_TYPE_RcsID", "A_ARG_TYPE_AVTransportID": "i4"
        case "Mute": "boolean"
        default: "string"
        }
    }
}
