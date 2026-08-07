import Foundation

public final class RecognitionProxyScanRuntime: LocalScanRuntime, @unchecked Sendable {
    private let baseURL: URL
    private let functionKey: String
    private let transport: HttpTransport

    public init(
        baseURL: URL,
        functionKey: String,
        transport: HttpTransport = URLSessionTransport(session: .shared))
    {
        self.baseURL = baseURL
        self.functionKey = functionKey
        self.transport = transport
    }

    public func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/scan"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(functionKey, forHTTPHeaderField: "x-functions-key")

        var body = Data()
        body.appendRecognitionProxyMultipartField("clientScanId", value: clientScanId.uuidString, boundary: boundary)
        if let capturedAtIso {
            body.appendRecognitionProxyMultipartField("capturedAt", value: capturedAtIso, boundary: boundary)
        }
        body.appendRecognitionProxyMultipartFile(
            "image",
            filename: "scan.jpg",
            mimeType: "image/jpeg",
            data: imageData,
            boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        return try await send(request)
    }

    public func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse {
        throw ApiClientError.httpError(
            501,
            ApiError(
                code: "local_resolution_not_configured",
                message: "Local scan resolution is not configured yet.",
                retryable: false,
                requestId: requestId))
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ApiClientError.invalidResponse }

        let decoder = JSONDecoder()
        if (200..<300).contains(http.statusCode) {
            return try decoder.decode(T.self, from: data)
        }

        let envelope = try? decoder.decode(ApiErrorEnvelope.self, from: data)
        throw ApiClientError.httpError(http.statusCode, envelope?.error)
    }
}

private extension Data {
    mutating func appendRecognitionProxyMultipartField(_ name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendRecognitionProxyMultipartFile(
        _ name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String)
    {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
