import XCTest
@testable import UnraidGatewayKit

final class PathAndDecodingTests: XCTestCase {
    func testPathHelpers() {
        XCTAssertEqual(GatewayPath.clean("a//b/../c/"), "/a/c")
        XCTAssertEqual(GatewayPath.clean("/../x"), "/x")
        XCTAssertEqual(GatewayPath.parent("/documents/a/b.txt"), "/documents/a")
        XCTAssertEqual(GatewayPath.parent("/documents"), "/")
        XCTAssertEqual(GatewayPath.parent("/"), "/")
        XCTAssertEqual(GatewayPath.name("/documents/a/b.txt"), "b.txt")
        XCTAssertEqual(GatewayPath.join("/", "documents"), "/documents")
        XCTAssertEqual(GatewayPath.join("/documents", "x"), "/documents/x")
        XCTAssertEqual(GatewayPath.depth("/"), 0)
        XCTAssertEqual(GatewayPath.depth("/documents/x"), 2)
    }

    func testDecodesGatewayEntry() throws {
        let json = #"{"name":"hello.txt","path":"/documents/hello.txt","type":"file","size":18,"mtime":"2026-09-08T14:01:19.326218029Z","etag":"\"12-18d35d50f76ec72d\"","mode":"-rw-rw-r--"}"#
        let e = try GatewayJSON.decoder.decode(FSEntry.self, from: Data(json.utf8))
        XCTAssertEqual(e.name, "hello.txt")
        XCTAssertFalse(e.isDirectory)
        XCTAssertEqual(e.size, 18)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: e.mtime), 2026)
    }

    func testDecodesChangesPage() throws {
        let json = #"{"path":"/media","since":0,"cursor":1757340191000000000,"dirs":["/media","/media/a"],"files":[],"truncated":true,"next":"/media/a/x.jpg","scanned":65580}"#
        let p = try GatewayJSON.decoder.decode(ChangesPage.self, from: Data(json.utf8))
        XCTAssertTrue(p.truncated)
        XCTAssertEqual(p.next, "/media/a/x.jpg")
        XCTAssertEqual(p.dirs.count, 2)
    }

    func testDecodesDashboardSample() throws {
        let json = #"{"array":{"state":"STARTED","capacity":{"kilobytes":{"free":"8459410862","used":"9538660024","total":"17998070886"}},"disks":[{"name":"disk1","status":"DISK_OK","temp":45,"fsSize":17998070886,"fsFree":8459410862}],"parityCheckStatus":{"status":"RUNNING","progress":89,"running":true}},"shares":[{"name":"documents","free":10193582739,"used":9800498323,"comment":""}],"docker":{"containers":[{"id":"x","names":["/unraid-gateway"],"state":"RUNNING","image":"ghcr.io/sidimam/unraid-gateway:latest","autoStart":false,"isUpdateAvailable":false,"webUiUrl":"http://192.168.0.100:8484/","iconUrl":null}]},"info":{"os":{"hostname":"nas","uptime":"2026-09-01T00:00:00Z","release":"7.3.2"},"cpu":{"brand":"Intel","cores":6,"threads":12}},"notifications":{"overview":{"unread":{"total":0,"warning":0,"alert":0}}},"metrics":{"cpu":{"percentTotal":3.2},"memory":{"percentTotal":21.5,"used":1,"total":2}}}"#
        let d = try GatewayJSON.decoder.decode(Dashboard.self, from: Data(json.utf8))
        XCTAssertEqual(d.array?.state, "STARTED")
        XCTAssertEqual(d.docker?.containers.first?.displayName, "unraid-gateway")
        XCTAssertEqual(d.arrayBytes?.total, 17998070886 * 1024)
    }

    func testServerStoreRoundTrip() {
        // Uses the standard defaults on macOS (no app group container in tests).
        let store = ServerStore()
        let before = store.all()
        let s = ServerConfig(name: "nas", url: URL(string: "http://192.168.0.100:8484")!)
        store.upsert(s)
        XCTAssertEqual(store.server(id: s.id)?.name, "nas")
        store.remove(id: s.id)
        XCTAssertEqual(store.all().count, before.count)
    }
}

final class ProxyInterceptionTests: XCTestCase {
    func testHTMLResponseIsReportedAsInterception() {
        let url = URL(string: "https://x.cloudflareaccess.com/cdn-cgi/access/login/gw")!
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        XCTAssertThrowsError(try GatewayClient.check(resp, Data("<!DOCTYPE html>".utf8))) { err in
            guard case GatewayError.interceptedByProxy(let host) = err else { return XCTFail("\(err)") }
            XCTAssertEqual(host, "x.cloudflareaccess.com")
            XCTAssertTrue((err as? GatewayError)?.errorDescription?.contains("Cloudflare Access") == true)
        }
    }
    func testJSONResponsePasses() throws {
        let url = URL(string: "https://gw.example.com/api/v1/fs/list")!
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        XCTAssertNoThrow(try GatewayClient.check(resp, Data("{}".utf8)))
    }
}

final class CloudflareTokenParsingTests: XCTestCase {
    func testParsesLabelledLinesAndBareValues() {
        let both = "CF-Access-Client-Id: 8297915feda35f08aaaa.access\nCF-Access-Client-Secret: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n"
        let p = CloudflareServiceToken.parse(both)
        XCTAssertEqual(p.clientID, "8297915feda35f08aaaa.access")
        XCTAssertEqual(p.clientSecret?.count, 64)
        XCTAssertEqual(CloudflareServiceToken.parse("cf-access-client-id: abc.access").clientID, "abc.access")
        XCTAssertEqual(CloudflareServiceToken.parse("abc.access").clientID, "abc.access")
        XCTAssertEqual(CloudflareServiceToken.parse(String(repeating: "f", count: 64)).clientSecret?.count, 64)
        XCTAssertNil(CloudflareServiceToken.parse("").clientID)
    }
}
