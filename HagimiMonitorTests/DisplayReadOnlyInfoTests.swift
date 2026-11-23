import CoreGraphics
import Testing
@testable import HagimiMonitorDirect

struct DisplayReadOnlyInfoTests {
    private func makeInfo(id: CGDirectDisplayID, name: String, isBuiltIn: Bool = false) -> DisplayInfo {
        DisplayInfo(
            id: id,
            name: name,
            isBuiltIn: isBuiltIn,
            resolution: "3840×2400",
            refreshRate: "60 Hz",
            hdrSupported: false,
            hdrActive: false,
            colorDepth: "--",
            sizeInches: nil,
            ppi: nil,
            hidpiScale: 2,
            adaptiveSync: nil,
            gamut: nil,
            manufacturer: nil,
            model: nil,
            serial: nil,
            manufactureDate: nil
        )
    }

    @Test func keepsVirtualDisplaysAndPreservesOrder() {
        let collected = [
            makeInfo(id: 1, name: "Built-in", isBuiltIn: true),
            makeInfo(id: 4, name: "UU远程"),
            makeInfo(id: 9, name: "Sidecar"),
        ]
        let kinds: [CGDirectDisplayID: DisplayKind] = [1: .builtIn, 4: .virtual, 9: .virtual]

        let result = DisplaySection.readOnlyDisplays(
            from: collected,
            coveredDisplayIDs: [1],
            classify: { kinds[$0] ?? .unsupported },
            isVendorModelZero: { _ in false }
        )

        #expect(result.map(\.id) == [4, 9])
    }

    @Test func excludesPhysicalBuiltInAndExternalDisplaysEvenWhenUncovered() {
        let collected = [
            makeInfo(id: 1, name: "Built-in", isBuiltIn: true),
            makeInfo(id: 2, name: "Dell U2723QE"),
            makeInfo(id: 3, name: "Studio Display"),
        ]
        let kinds: [CGDirectDisplayID: DisplayKind] = [1: .builtIn, 2: .externalDDC, 3: .appleNative]

        let result = DisplaySection.readOnlyDisplays(
            from: collected,
            coveredDisplayIDs: [],
            classify: { kinds[$0] ?? .unsupported },
            isVendorModelZero: { _ in false }
        )

        #expect(result.isEmpty)
    }

    @Test func excludesDummyDisplays() {
        let collected = [
            makeInfo(id: 5, name: "Dummy Display"),
            makeInfo(id: 6, name: "AirPlay"),
        ]
        let kinds: [CGDirectDisplayID: DisplayKind] = [5: .dummy, 6: .virtual]

        let result = DisplaySection.readOnlyDisplays(
            from: collected,
            coveredDisplayIDs: [],
            classify: { kinds[$0] ?? .unsupported },
            isVendorModelZero: { $0 == 5 }
        )

        #expect(result.map(\.id) == [6])
    }

    @Test func keepsUncoveredNonBuiltInNonDummyWhenVendorAndModelAreZero() {
        let collected = [
            makeInfo(id: 1, name: "Built-in Zero", isBuiltIn: true),
            makeInfo(id: 7, name: "Virtual Framebuffer"),
        ]
        let kinds: [CGDirectDisplayID: DisplayKind] = [1: .builtIn, 7: .externalDDC]

        let result = DisplaySection.readOnlyDisplays(
            from: collected,
            coveredDisplayIDs: [],
            classify: { kinds[$0] ?? .unsupported },
            isVendorModelZero: { _ in true }
        )

        #expect(result.map(\.id) == [7])
    }

    @Test func excludesDisplaysAlreadyCoveredByControlOrConnectionList() {
        let collected = [
            makeInfo(id: 4, name: "UU远程"),
            makeInfo(id: 7, name: "Zero ID Screen"),
        ]
        let kinds: [CGDirectDisplayID: DisplayKind] = [4: .virtual, 7: .externalDDC]

        let result = DisplaySection.readOnlyDisplays(
            from: collected,
            coveredDisplayIDs: [4, 7],
            classify: { kinds[$0] ?? .unsupported },
            isVendorModelZero: { $0 == 7 }
        )

        #expect(result.isEmpty)
    }
}
