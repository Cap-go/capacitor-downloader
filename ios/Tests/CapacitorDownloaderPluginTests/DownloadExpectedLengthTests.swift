import XCTest
@testable import CapacitorDownloaderPlugin

final class DownloadExpectedLengthTests: XCTestCase {
    func testParsePositiveHeaderValue() {
        XCTAssertNil(DownloadExpectedLength.parsePositiveHeaderValue(nil))
        XCTAssertNil(DownloadExpectedLength.parsePositiveHeaderValue(""))
        XCTAssertNil(DownloadExpectedLength.parsePositiveHeaderValue("0"))
        XCTAssertEqual(DownloadExpectedLength.parsePositiveHeaderValue(" 2048 "), 2048)
    }

    func testHeaderLookupIsCaseInsensitive() throws {
        let url = URL(string: "https://example.com/file")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["x-uncompressed-length": "500"]
        )!
        XCTAssertEqual(DownloadExpectedLength.parse(from: response, headerName: "X-Uncompressed-Length"), 500)
    }

    func testParseRejectsNonNumericAndOverflow() {
        XCTAssertNil(DownloadExpectedLength.parsePositiveHeaderValue("not-a-number"))
        XCTAssertNil(DownloadExpectedLength.parsePositiveHeaderValue("9223372036854775808"))
    }

    func testParseIgnoresMissingLengthHeaderOnResponse() throws {
        let url = URL(string: "https://example.com/file")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!
        XCTAssertNil(DownloadExpectedLength.parse(from: response, headerName: "X-Uncompressed-Length"))
    }
}