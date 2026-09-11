import XCTest
@testable import UnraidGatewayKit

final class ArchiveTests: XCTestCase {
    func testZipAndEPUB() throws {
        let data = try XCTUnwrap(Data(base64Encoded: Fixtures.epubBase64))
        let zip = try XCTUnwrap(ZipArchive(data: data))
        XCTAssertEqual(zip.entries.count, 5)
        XCTAssertEqual(zip.read(named: "mimetype").flatMap { String(data: $0, encoding: .utf8) }, "application/epub+zip") // stored
        XCTAssertTrue(zip.read(named: "OEBPS/ch1.xhtml").flatMap { String(data: $0, encoding: .utf8) }?.contains("Chapter One") == true) // deflate
        let book = EPUBBook.parse(zip)
        XCTAssertEqual(book.title, "Test Book")
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].title, "One")
        XCTAssertTrue(book.chapters[0].text.hasPrefix("Chapter One\n\nHello & welcome"))
        XCTAssertTrue(book.chapters[0].text.contains("\n\nSecond paragraph."))
    }

    func testFileKinds() {
        XCTAssertEqual(FileKind.of(name: "movie.MKV", isDirectory: false), .mpvVideo)
        XCTAssertEqual(FileKind.of(name: "clip.mp4", isDirectory: false), .video)
        XCTAssertEqual(FileKind.of(name: "notes.nfo", isDirectory: false), .text)
        XCTAssertEqual(FileKind.of(name: "book.epub", isDirectory: false), .epub)
        XCTAssertEqual(FileKind.of(name: "issue.cbz", isDirectory: false), .comic)
        XCTAssertEqual(FileKind.of(name: "README", isDirectory: false), .text)
        XCTAssertEqual(FileKind.of(name: "x", isDirectory: true), .folder)
        XCTAssertEqual(FileKind.of(name: "thing.bin", isDirectory: false), .other)
        XCTAssertTrue(FileKind.mpvAudio.needsMPV); XCTAssertTrue(FileKind.audio.isNativeMedia)
    }
}
