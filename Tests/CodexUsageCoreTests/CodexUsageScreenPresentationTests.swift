import Foundation
import XCTest

final class CodexUsageScreenPresentationTests: XCTestCase {
    func testUsageHeaderSharesTheTopRowWithRefresh() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageApp/AgentUsageView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("InfoCard(title: \"Usage\")"))
        XCTAssertTrue(source.contains(".overlay(alignment: .topTrailing)"))
        XCTAssertFalse(source.contains(
            "InfoCard(title: status?.provider.rawValue"
        ))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
