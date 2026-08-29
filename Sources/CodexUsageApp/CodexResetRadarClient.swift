import CodexUsageCore
import Foundation

struct CodexResetRadarClient: Sendable {
    static let endpoint = URL(
        string: "https://codex-resets.com/api/v1/status"
    )!
    static let publicMonitorEndpoint = URL(string: "https://codexreset.org/")!

    private let session: URLSession
    private let endpoint: URL
    private let publicMonitorEndpoint: URL

    init(
        session: URLSession = .shared,
        endpoint: URL = CodexResetRadarClient.endpoint,
        publicMonitorEndpoint: URL = CodexResetRadarClient.publicMonitorEndpoint
    ) {
        self.session = session
        self.endpoint = endpoint
        self.publicMonitorEndpoint = publicMonitorEndpoint
    }

    func fetch() async throws -> CodexResetRadarSnapshot {
        let statusRequest = request(for: endpoint, accept: "application/json")
        let monitorRequest = request(for: publicMonitorEndpoint, accept: "text/html")
        async let statusResult = session.data(for: statusRequest)
        async let monitorResult = try? session.data(for: monitorRequest)

        let (data, response) = try await statusResult
        guard isSuccessful(response) else {
            throw CodexResetRadarClientError.invalidResponse
        }
        let snapshot = try CodexResetRadarSnapshot.decode(data)

        guard let (monitorData, monitorResponse) = await monitorResult,
              isSuccessful(monitorResponse)
        else {
            return snapshot
        }
        return snapshot.withLatestPost(
            CodexTiboPost.decodePublicMonitorHTML(monitorData)
        )
    }

    private func request(for url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func isSuccessful(_ response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(httpResponse.statusCode)
    }
}

private enum CodexResetRadarClientError: Error {
    case invalidResponse
}
