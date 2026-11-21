import Testing
@testable import HagimiMonitorDirect

struct UpdateServiceTests {
    @Test(arguments: ["1.7.9", "1.8.0", "1.8", ""])
    func staleUpdateVersionsAreHidden(_ version: String) {
        #expect(UpdateService.newerDisplayVersion(version, than: "1.8.0") == nil)
    }

    @Test func newerUpdateUsesNumericVersionOrdering() {
        #expect(UpdateService.newerDisplayVersion("1.10.0", than: "1.9.0") == "1.10.0")
    }
}
