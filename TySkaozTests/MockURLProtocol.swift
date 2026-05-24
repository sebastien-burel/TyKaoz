import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stub: (data: Data, status: Int)?
    nonisolated(unsafe) static var stubError: URLError?

    static func session(data: Data, status: Int) -> URLSession {
        stub = (data, status)
        stubError = nil
        return makeSession()
    }

    static func session(error: URLError) -> URLSession {
        stub = nil
        stubError = error
        return makeSession()
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private let queue = DispatchQueue(label: "MockURLProtocol.delivery")

    override func startLoading() {
        // Capture stub state at startLoading time so a concurrent test cannot
        // race the delivery dispatched below.
        let stub = MockURLProtocol.stub
        let stubError = MockURLProtocol.stubError
        // Deliver asynchronously so URLSession.bytes(for:) properly initializes
        // its AsyncBytes pipeline before bytes arrive.
        queue.async { [weak self] in
            guard let self else { return }
            if let stubError {
                self.client?.urlProtocol(self, didFailWithError: stubError)
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
            // Push the body in small chunks so the AsyncBytes line splitter has the
            // opportunity to emit lines progressively (mirrors real streaming).
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
