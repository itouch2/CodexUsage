import Foundation
import XCTest

final class AppIconPackagingTests: XCTestCase {
    func testIconSourceAndPackagingContract() throws {
        let root = repositoryRoot
        let sourceURL = root.appendingPathComponent(
            "Resources/AppIcon/CodexUsage.icon"
        )
        let plist = try sourceText(at: "Packaging/Info.plist.in")
        let packageScript = try sourceText(at: "scripts/package_app.sh")
        let compiler = try sourceText(at: "scripts/compile_app_icon.sh")
        let bloom = try String(
            contentsOf: sourceURL.appendingPathComponent(
                "Assets/codex-bloom.svg"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        for asset in [
            "icon.json",
            "Assets/codex-bloom.svg",
            "Assets/terminal-arrow.svg",
            "Assets/progress-track.svg",
            "Assets/progress-fill.svg"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: sourceURL.appendingPathComponent(asset).path
            ))
        }
        XCTAssertTrue(plist.contains("<key>CFBundleIconName</key>"))
        XCTAssertTrue(plist.contains("<string>CodexUsage</string>"))
        XCTAssertTrue(packageScript.contains("compile_app_icon.sh"))
        XCTAssertFalse(packageScript.contains("generate_app_icon.sh"))
        XCTAssertTrue(compiler.contains("xcrun --find actool"))
        XCTAssertTrue(compiler.contains("--app-icon CodexUsage"))
        XCTAssertTrue(compiler.contains("Assets.car"))
        XCTAssertTrue(bloom.contains("id=\"cloud-shape\""))
        XCTAssertTrue(bloom.contains("id=\"cloud-base\""))
        XCTAssertFalse(bloom.contains("radialGradient"))
        XCTAssertFalse(bloom.contains("pink-light"))
        XCTAssertFalse(bloom.contains("blue-light"))
        XCTAssertTrue(bloom.contains("#8D82E3"))
        XCTAssertTrue(bloom.contains("#6B5FD6"))

        let icon = try String(
            contentsOf: sourceURL.appendingPathComponent("icon.json"),
            encoding: .utf8
        )
        let arrow = try String(
            contentsOf: sourceURL.appendingPathComponent(
                "Assets/terminal-arrow.svg"
            ),
            encoding: .utf8
        )
        let track = try String(
            contentsOf: sourceURL.appendingPathComponent(
                "Assets/progress-track.svg"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(icon.contains("Terminal Arrow"))
        XCTAssertTrue(icon.contains(
            "extended-srgb:1.00000,1.00000,1.00000,1.00000"
        ))
        XCTAssertTrue(arrow.contains("id=\"pearl-white\""))
        XCTAssertTrue(arrow.contains("stroke-linecap=\"round\""))
        XCTAssertTrue(track.contains("fill-rule=\"evenodd\""))
    }

    private func sourceText(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
