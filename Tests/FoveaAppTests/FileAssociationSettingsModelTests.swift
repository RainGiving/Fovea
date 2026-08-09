import UniformTypeIdentifiers
import XCTest
import FoveaCore
@testable import FoveaApp

@MainActor
final class FileAssociationSettingsModelTests: XCTestCase {
    func testCommonAndExpandedFormatOrdering() {
        let model = makeModel()
        XCTAssertEqual(model.visibleFormats, [.jpeg, .png, .gif, .webp, .heic])

        model.setShowsAllFormats(true)

        XCTAssertEqual(model.visibleFormats, [
            .jpeg, .png, .gif, .webp, .heic,
            .tiff, .bmp, .heif, .avif, .svg
        ])
    }

    func testSelectCommonFormatsPreservesExtraSelections() {
        let model = makeModel()
        model.toggleSelection(for: .svg)

        model.selectCommonFormats()

        XCTAssertEqual(model.selectedFormats, Set([
            .jpeg, .png, .gif, .webp, .heic, .svg
        ]))
    }

    func testCollapsePreservesHiddenSelection() {
        let model = makeModel()
        model.setShowsAllFormats(true)
        model.toggleSelection(for: .avif)

        model.setShowsAllFormats(false)

        XCTAssertTrue(model.selectedFormats.contains(.avif))
    }

    func testRefreshReportsFoveaAndOtherApplicationNames() {
        let foveaURL = URL(fileURLWithPath: "/Applications/Fovea.app")
        let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")
        let service = DefaultApplicationServiceFake(defaults: [
            UTType.jpeg: foveaURL,
            UTType.png: previewURL
        ])
        let resolver = ApplicationBundleResolverFake(
            validated: ApplicationBundleInfo(url: foveaURL, bundleIdentifier: "com.example.Fovea", displayName: "Fovea"),
            bundles: [previewURL: ApplicationBundleInfo(url: previewURL, bundleIdentifier: "com.apple.Preview", displayName: "Preview")]
        )
        let model = makeModel(service: service, appURL: foveaURL, resolver: resolver)

        model.refreshStatuses()

        XCTAssertEqual(model.rows[.jpeg]?.defaultApplicationName, "Fovea")
        XCTAssertTrue(model.rows[.jpeg]?.isFoveaDefault == true)
        XCTAssertEqual(model.rows[.png]?.defaultApplicationName, "Preview")
    }

    func testRefreshUsesLocalizedBundleNameAndBundleIdentifierForIdentity() {
        let fovea = ApplicationBundleInfo(
            url: URL(fileURLWithPath: "/Applications/Renamed.app"),
            bundleIdentifier: "com.example.Fovea",
            displayName: "Localized Fovea"
        )
        let otherCopy = URL(fileURLWithPath: "/Volumes/Other/Fovea.app")
        let service = DefaultApplicationServiceFake(defaults: [.jpeg: otherCopy])
        let resolver = ApplicationBundleResolverFake(
            validated: fovea,
            bundles: [otherCopy: ApplicationBundleInfo(url: otherCopy, bundleIdentifier: "com.example.Fovea", displayName: "另一份 Fovea")]
        )
        let model = makeModel(service: service, resolver: resolver)

        model.refreshStatuses()

        XCTAssertEqual(model.rows[.jpeg]?.defaultApplicationName, "另一份 Fovea")
        XCTAssertTrue(model.rows[.jpeg]?.isFoveaDefault == true)
    }

    func testRefreshDoesNotTreatMissingApplicationURLsAsFoveaDefault() {
        let model = makeModel(service: DefaultApplicationServiceFake(), appURL: nil)

        model.refreshStatuses()

        XCTAssertFalse(model.rows[.jpeg]?.isFoveaDefault == true)
    }

    func testApplyChangesOnlySelectedFormatsAndClearsSuccesses() async {
        let service = DefaultApplicationServiceFake()
        let model = makeModel(service: service)
        model.toggleSelection(for: .jpeg)
        model.toggleSelection(for: .png)

        await model.applySelectedFormats()

        XCTAssertEqual(service.setTypes, [.jpeg, .png])
        XCTAssertTrue(model.selectedFormats.isEmpty)
        XCTAssertEqual(model.summary, .success(count: 2))
    }

    func testPartialFailureKeepsOnlyFailedFormatSelected() async {
        let service = DefaultApplicationServiceFake(failingTypes: [.png])
        let model = makeModel(service: service)
        model.toggleSelection(for: .jpeg)
        model.toggleSelection(for: .png)

        await model.applySelectedFormats()

        XCTAssertEqual(model.selectedFormats, [.png])
        XCTAssertEqual(model.summary, .partialSuccess(succeeded: 1, failed: 1))
        XCTAssertEqual(model.rows[.png]?.error, .service("Denied"))
    }

    func testAllFailureSummaryAndSecondApplyRetriesSuccessfully() async {
        let service = DefaultApplicationServiceFake(failingTypes: [.jpeg, .png])
        let model = makeModel(service: service)
        model.toggleSelection(for: .jpeg)
        model.toggleSelection(for: .png)

        await model.applySelectedFormats()
        XCTAssertEqual(model.summary, .failure(count: 2))
        XCTAssertEqual(model.selectedFormats, [.jpeg, .png])

        service.failingTypes = []
        await model.applySelectedFormats()
        XCTAssertEqual(service.setTypes, [.jpeg, .png, .jpeg, .png])
        XCTAssertEqual(model.summary, .success(count: 2))
        XCTAssertTrue(model.selectedFormats.isEmpty)
    }

    func testApplyRefreshesStatuses() async {
        let service = DefaultApplicationServiceFake()
        let model = makeModel(service: service)
        model.toggleSelection(for: .jpeg)

        await model.applySelectedFormats()

        XCTAssertTrue(model.rows[.jpeg]?.isFoveaDefault == true)
    }

    func testHiddenUnselectedFormatsAreNotMutated() async {
        let service = DefaultApplicationServiceFake()
        let model = makeModel(service: service)
        model.toggleSelection(for: .jpeg)

        await model.applySelectedFormats()

        XCTAssertEqual(service.setTypes, [.jpeg])
    }

    func testInvalidApplicationBundlePreventsMutation() async {
        let service = DefaultApplicationServiceFake()
        let model = makeModel(service: service, appURL: nil)
        model.toggleSelection(for: .gif)

        await model.applySelectedFormats()

        XCTAssertTrue(service.setTypes.isEmpty)
        XCTAssertEqual(model.summary, .invalidApplicationBundle)
        XCTAssertEqual(model.selectedFormats, [.gif])
    }
}

@MainActor
private final class DefaultApplicationServiceFake: DefaultApplicationServicing {
    var defaults: [UTType: URL]
    var failingTypes: Set<UTType>
    var setTypes: [UTType] = []

    init(defaults: [UTType: URL] = [:], failingTypes: Set<UTType> = []) {
        self.defaults = defaults
        self.failingTypes = failingTypes
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? {
        defaults[contentType]
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        setTypes.append(contentType)
        if failingTypes.contains(contentType) { throw TestFailure.denied }
        defaults[contentType] = applicationURL
    }
}

private enum TestFailure: LocalizedError {
    case denied
    var errorDescription: String? { "Denied" }
}

@MainActor
private func makeModel(
    service: DefaultApplicationServicing = DefaultApplicationServiceFake(),
    appURL: URL? = URL(fileURLWithPath: "/Applications/Fovea.app"),
    resolver: ApplicationBundleResolving? = nil
) -> FileAssociationSettingsModel {
    let info = appURL.map { ApplicationBundleInfo(url: $0, bundleIdentifier: "com.example.Fovea", displayName: "Fovea") }
    return FileAssociationSettingsModel(
        service: service,
        applicationURL: { appURL },
        bundleResolver: resolver ?? ApplicationBundleResolverFake(validated: info)
    )
}

private final class ApplicationBundleResolverFake: ApplicationBundleResolving {
    let validated: ApplicationBundleInfo?
    let bundles: [URL: ApplicationBundleInfo]

    init(validated: ApplicationBundleInfo?, bundles: [URL: ApplicationBundleInfo] = [:]) {
        self.validated = validated
        self.bundles = bundles
    }

    func validatedRunningApplication(at url: URL?) -> ApplicationBundleInfo? { validated }
    func application(at url: URL) -> ApplicationBundleInfo? { bundles[url] ?? (validated?.url == url ? validated : nil) }
}
