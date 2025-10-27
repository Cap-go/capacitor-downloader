import XCTest
@testable import CapacitorAccelerometerPlugin

final class CapacitorAccelerometerPluginTests: XCTestCase {
    func testPluginInitialises() {
        let plugin = CapacitorAccelerometerPlugin()
        XCTAssertEqual(plugin.identifier, "CapacitorAccelerometerPlugin")
    }
}
