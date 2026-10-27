import XCTest
@testable import Boreal

final class RegressionTests: XCTestCase {
    func testAutoWithUnavailableBounds() throws { XCTAssertEqual(try FanRule().target(minimum: .nan, maximum: .nan, temperatures: [:]), -1) }
    func testSensorRejectsUnreasonableMaximum() { XCTAssertThrowsError(try FanRule(mode: .sensor).target(minimum: 1000, maximum: 30000, temperatures: ["TC0P":60])) }
    func testSensorRejectsNaN() { XCTAssertThrowsError(try FanRule(mode: .sensor).target(minimum: 1000, maximum: 5000, temperatures: ["TC0P":.nan])) }
    func testSensorRejectsZero() { XCTAssertThrowsError(try FanRule(mode: .sensor).target(minimum: 1000, maximum: 5000, temperatures: ["TC0P":0])) }
    func testFixedRejectsInfinity() { XCTAssertThrowsError(try FanRule(mode: .fixed,rpm:.infinity).target(minimum: 1000, maximum: 5000, temperatures: [:])) }
    func testFixedEndpoints() throws { for rpm in [1000.0, 5000.0] { XCTAssertEqual(try FanRule(mode:.fixed,rpm:rpm).target(minimum:1000,maximum:5000,temperatures:[:]),rpm) } }
    func testInvalidSensorKeys() { for key in ["TC\nP", "T€", "", "12345", "TC\0P"] { XCTAssertFalse(validSensorKey(key)) }; XCTAssertTrue(validSensorKey("TC0P")) }
    func testEmptyProfileRejected() { XCTAssertThrowsError(try FanProfile(name:"A",rules:[:]).validated()) }
    func testWhitespaceNameRejected() { XCTAssertThrowsError(try FanProfile(name:"  ",rules:[0:FanRule()]).validated()) }
    func testControlCharactersRejected() { XCTAssertThrowsError(try FanProfile(name:"A\nB",rules:[0:FanRule()]).validated()) }
    func testLongNameRejected() { XCTAssertThrowsError(try FanProfile(name:String(repeating:"a",count:61),rules:[0:FanRule()]).validated()) }
    func testNameTrimmed() throws { XCTAssertEqual(try FanProfile(name:" A ",rules:[0:FanRule()]).validated().name,"A") }
    func testInvalidFanIndexRejected() { for index in [-1,10] { XCTAssertThrowsError(try FanProfile(name:"A",rules:[index:FanRule()]).validated()) } }
    func testInvalidProfileRPMRejected() { XCTAssertThrowsError(try FanProfile(name:"A",rules:[0:FanRule(rpm:20001)]).validated()) }
    func testInvalidProfileThresholdsRejected() { XCTAssertThrowsError(try FanProfile(name:"A",rules:[0:FanRule(start:80,full:50)]).validated()) }
    func testPreferenceVersionRejected() { var p=Preferences(); p.version=2; XCTAssertThrowsError(try p.validated()) }
    func testAppearanceRejected() { var p=Preferences(); p.appearance="invalid"; XCTAssertThrowsError(try p.validated()) }
    func testMenuFanRejected() { var p=Preferences(); p.menuFan=10; XCTAssertThrowsError(try p.validated()) }
    func testMenuSensorRejected() { var p=Preferences(); p.menuSensor="bad"; XCTAssertThrowsError(try p.validated()) }
    func testDuplicateProfileIDsRejected() { var p=Preferences(); let profile=FanProfile(name:"A",rules:[0:FanRule()]); p.profiles=[profile,profile]; XCTAssertThrowsError(try p.validated()) }
    func testProfileCountBounded() { var p=Preferences(); p.profiles=(0..<101).map { FanProfile(name:"P\($0)",rules:[0:FanRule()]) }; XCTAssertThrowsError(try p.validated()) }
    func testDefaultPreferencesValid() throws { _ = try Preferences().validated() }
    func testCSVQuotes() { XCTAssertEqual(csvField("a,\"b\"\nc"),"\"a,\"\"b\"\"\nc\"") }
}
