import Foundation

/// URLProtocol stub used in tests. Each `session(...)` call mints a unique
/// token, registered in a thread-safe table; the matching session attaches
/// the token to every request via `httpAdditionalHeaders`. At load time the
/// protocol resolves its stub by token, so concurrent test suites can't
/// clobber each other's mock state.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var dataStubs: [String: (data: Data, status: Int)] = [:]
    nonisolated(unsafe) private static var errorStubs: [String: URLError] = [:]

    private static let tokenHeader = "X-MockURLProtocol-Token"

    static func session(data: Data, status: Int) -> URLSession {
        let token = UUID().uuidString
        lock.withLock { dataStubs[token] = (data, status) }
        return makeSession(token: token)
    }

    static func session(error: URLError) -> URLSession {
        let token = UUID().uuidString
        lock.withLock { errorStubs[token] = error }
        return makeSession(token: token)
    }

    private static func makeSession(token: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private let queue = DispatchQueue(label: "MockURLProtocol.delivery")

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: Self.tokenHeader) ?? ""
        let (stub, errorStub): ((data: Data, status: Int)?, URLError?) = Self.lock.withLock {
            (Self.dataStubs[token], Self.errorStubs[token])
        }

        queue.async { [weak self] in
            guard let self else { return }
            if let errorStub {
                self.client?.urlProtocol(self, didFailWithError: errorStub)
                return
            }
            guard let stub,
                  let response = HTTPURLResponse(
                      url: self.request.url!,
                      statusCode: stub.status,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/x-ndjson"]
                  )
            else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Push in small chunks so URLSession.bytes(for:) processes them
            // progressively, mirroring real streaming.
            let chunkSize = 32
            var offset = 0
            while offset < stub.data.count {
                let end = min(offset + chunkSize, stub.data.count)
                self.client?.urlProtocol(self, didLoad: stub.data.subdata(in: offset..<end))
                offset = end
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
