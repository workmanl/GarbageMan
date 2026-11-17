import XCTest

final class SimulatorCleanerTests: XCTestCase {

    func testParsesUnavailableDevices() {
        let json = """
        {
          "devices" : {
            "com.apple.CoreSimulator.SimRuntime.iOS-17-0" : [
              { "udid" : "BBB", "isAvailable" : false, "name" : "iPhone 15" },
              { "udid" : "AAA", "isAvailable" : false, "name" : "iPad" }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0" : [
              { "udid" : "CCC", "isAvailable" : true, "name" : "iPhone 17 Pro" }
            ]
          }
        }
        """
        XCTAssertEqual(SimulatorCleaner.unavailableUDIDs(fromSimctlJSON: Data(json.utf8)), ["AAA", "BBB"])
    }

    func testEmptyListing() {
        let json = #"{ "devices" : { "com.apple.CoreSimulator.SimRuntime.iOS-27-0" : [ ] } }"#
        XCTAssertTrue(SimulatorCleaner.unavailableUDIDs(fromSimctlJSON: Data(json.utf8)).isEmpty)
    }

    func testGarbageInput() {
        XCTAssertTrue(SimulatorCleaner.unavailableUDIDs(fromSimctlJSON: Data("not json".utf8)).isEmpty)
    }
}
