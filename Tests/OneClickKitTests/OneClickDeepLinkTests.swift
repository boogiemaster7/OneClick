import Foundation
import Testing
@testable import OneClickKit

@Suite("OneClickDeepLink")
struct OneClickDeepLinkTests {

    @Test("steam link round-trips through url and back")
    func steamRoundTrip() throws {
        let link = OneClickDeepLink.playSteam(appID: 440)
        #expect(link.url.absoluteString == "oneclick://play/steam/440")
        #expect(OneClickDeepLink(url: link.url) == link)
    }

    @Test("manual link round-trips through url and back")
    func manualRoundTrip() throws {
        let id = UUID()
        let link = OneClickDeepLink.playManual(id: id)
        #expect(link.url.absoluteString == "oneclick://play/manual/\(id.uuidString)")
        #expect(OneClickDeepLink(url: link.url) == link)
    }

    @Test("manual UUID parses case-insensitively (open may lowercase the URL)")
    func manualLowercasedUUID() throws {
        let id = UUID()
        let lowered = URL(string: "oneclick://play/manual/\(id.uuidString.lowercased())")!
        #expect(OneClickDeepLink(url: lowered) == .playManual(id: id))
    }

    @Test("scheme is matched case-insensitively")
    func schemeCaseInsensitive() {
        #expect(OneClickDeepLink(url: URL(string: "ONECLICK://play/steam/7")!) == .playSteam(appID: 7))
    }

    @Test("malformed links are rejected (fail closed)")
    func rejectsMalformed() {
        let bad = [
            "https://play/steam/440",         // wrong scheme
            "oneclick://open/steam/440",          // wrong host
            "oneclick://play/steam/notanumber",   // non-numeric appID
            "oneclick://play/steam",              // missing id
            "oneclick://play/steam/440/extra",    // too many components
            "oneclick://play/manual/not-a-uuid",  // malformed UUID
            "oneclick://play/xbox/440",           // unknown kind
            "oneclick://play",                    // no path
        ]
        for s in bad {
            #expect(OneClickDeepLink(url: URL(string: s)!) == nil, "should reject \(s)")
        }
    }

    @Test("bundleIDComponent is unique + stable per game kind")
    func bundleIDComponent() {
        #expect(OneClickDeepLink.playSteam(appID: 440).bundleIDComponent == "steam-440")
        let id = UUID()
        #expect(OneClickDeepLink.playManual(id: id).bundleIDComponent == "manual-\(id.uuidString.lowercased())")
    }
}
