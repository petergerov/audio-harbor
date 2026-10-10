#if os(macOS)
import Foundation

/// The device description and service descriptions players read before they browse.
enum MusicServerDocuments {
    static let deviceType = "urn:schemas-upnp-org:device:MediaServer:1"
    static let contentDirectory = "urn:schemas-upnp-org:service:ContentDirectory:1"
    static let connectionManager = "urn:schemas-upnp-org:service:ConnectionManager:1"
    static let services = [contentDirectory, connectionManager]

    static func description(name: String, udn: String, hasIcon: Bool) -> String {
        let services = services.map { type -> String in
            let name = UPnPXML.shortName(type)
            return "<service><serviceType>\(type)</serviceType><serviceId>urn:upnp-org:serviceId:\(name)</serviceId>"
                + "<SCPDURL>/scpd/\(name).xml</SCPDURL><controlURL>/ctl/\(name)</controlURL>"
                + "<eventSubURL>/evt/\(name)</eventSubURL></service>"
        }.joined()
        let icon = hasIcon
            ? "<iconList><icon><mimetype>image/png</mimetype><width>120</width><height>120</height><depth>32</depth>"
                + "<url>/icon.png</url></icon></iconList>"
            : ""
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:dlna="urn:schemas-dlna-org:device-1-0">
        <specVersion><major>1</major><minor>0</minor></specVersion>
        <device>
        <deviceType>\(deviceType)</deviceType>
        <friendlyName>\(UPnPXML.escape(name))</friendlyName>
        <manufacturer>Audio Harbor</manufacturer>
        <modelName>Audio Harbor</modelName>
        <modelNumber>\(UPnPXML.escape(Brand.versionLabel))</modelNumber>
        <UDN>\(udn)</UDN>
        <dlna:X_DLNADOC>DMS-1.50</dlna:X_DLNADOC>
        \(icon)<serviceList>\(services)</serviceList>
        </device>
        </root>
        """
    }

    static func actions(_ service: String) -> [UPnPXML.Action] {
        switch service {
        case "ContentDirectory":
            return [
                ("Browse", [("ObjectID", "in", "A_ARG_TYPE_ObjectID"), ("BrowseFlag", "in", "A_ARG_TYPE_BrowseFlag"),
                            ("Filter", "in", "A_ARG_TYPE_Filter"), ("StartingIndex", "in", "A_ARG_TYPE_Index"),
                            ("RequestedCount", "in", "A_ARG_TYPE_Count"), ("SortCriteria", "in", "A_ARG_TYPE_SortCriteria"),
                            ("Result", "out", "A_ARG_TYPE_Result"), ("NumberReturned", "out", "A_ARG_TYPE_Count"),
                            ("TotalMatches", "out", "A_ARG_TYPE_Count"), ("UpdateID", "out", "A_ARG_TYPE_UpdateID")]),
                ("GetSearchCapabilities", [("SearchCaps", "out", "SearchCapabilities")]),
                ("GetSortCapabilities", [("SortCaps", "out", "SortCapabilities")]),
                ("GetSystemUpdateID", [("Id", "out", "SystemUpdateID")]),
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

    static func scpd(_ service: String) -> String? {
        let list = actions(service)
        guard !list.isEmpty else { return nil }
        return UPnPXML.scpd(list, dataType: dataType, evented: service == "ContentDirectory" ? ["SystemUpdateID"] : [])
    }

    private static func dataType(_ variable: String) -> String {
        switch variable {
        case "A_ARG_TYPE_Index", "A_ARG_TYPE_Count", "A_ARG_TYPE_UpdateID", "SystemUpdateID": "ui4"
        case "A_ARG_TYPE_ConnectionID", "A_ARG_TYPE_RcsID", "A_ARG_TYPE_AVTransportID": "i4"
        default: "string"
        }
    }
}
#endif
