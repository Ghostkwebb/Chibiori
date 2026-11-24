import Foundation

struct MockStubResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let delay: TimeInterval

    init(
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data,
        delay: TimeInterval = 0
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.delay = delay
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handlers: [String: @Sendable (URLRequest) throws -> MockStubResponse] = [:]

    private let stateLock = NSLock()
    private var cancelled = false

    static func makeSession(handler: @escaping @Sendable (URLRequest) throws -> MockStubResponse) -> URLSession {
        let sessionID = UUID().uuidString
        lock.lock()
        handlers[sessionID] = handler
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["x-chibiori-mock-id": sessionID]
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func unregister(session: URLSession) {
        if let id = session.configuration.httpAdditionalHeaders?["x-chibiori-mock-id"] as? String {
            lock.lock()
            handlers.removeValue(forKey: id)
            lock.unlock()
        }
        session.invalidateAndCancel()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "x-chibiori-mock-id") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let sessionID = request.value(forHTTPHeaderField: "x-chibiori-mock-id") ?? ""
        Self.lock.lock()
        let handler = Self.handlers[sessionID]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        // URLRequest.httpBody may be moved to httpBodyStream by URLSession
        var normalizedRequest = request
        if normalizedRequest.httpBody == nil, let stream = normalizedRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            normalizedRequest.httpBody = data
        }

        let stub: MockStubResponse
        do {
            stub = try handler(normalizedRequest)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let deliver = { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let isCancelled = self.cancelled
            self.stateLock.unlock()
            guard !isCancelled else { return }

            guard let url = self.request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: stub.statusCode,
                      httpVersion: "HTTP/1.1",
                      headerFields: stub.headers
                  ) else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: stub.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if stub.delay > 0 {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + stub.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {
        stateLock.lock()
        cancelled = true
        stateLock.unlock()
    }
}
