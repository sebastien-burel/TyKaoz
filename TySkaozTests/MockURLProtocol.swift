import Foundation

final class MockURLProtocol: URLProtocol {
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

    override func startLoading() {
        if let stubError = MockURLProtocol.stubError {
            client?.urlProtocol(self, didFailWithError: stubError)
            return
        }
        guard let stub = MockURLProtocol.stub,
              let response = HTTPURLResponse(
                  url: request.url!,
                  statusCode: stub.status,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
