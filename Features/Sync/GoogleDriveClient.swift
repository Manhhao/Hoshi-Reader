import Foundation
import Network

enum GoogleDriveError: LocalizedError {
    case invalidResponse
    case apiError(String, statusCode: Int?)
    case unavailable(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Invalid response from Google Drive")
        case .apiError(let message, _):
            return message
        case .unavailable(let error):
            return error.localizedDescription
        }
    }
    
    var isStaleCacheError: Bool {
        switch self {
        case .apiError(_, let statusCode):
            return statusCode == 404
        default:
            return false
        }
    }
}

@MainActor
final class GoogleDriveClient {
    static let shared = GoogleDriveClient()
    private(set) var connectionId = 0
    private var isStopped = false
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let pathMonitor = NWPathMonitor()
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private init() {
        pathMonitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
    
    func stop() async {
        isStopped = true
        connectionId += 1
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                for task in tasks {
                    task.cancel()
                }
                continuation.resume()
            }
        }
    }
    
    func resume() {
        isStopped = false
    }
    
    func checkConnection(_ connection: Int) throws {
        if connection != connectionId {
            throw URLError(.cancelled)
        }
    }
    
    func request(
        _ path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        bodyFile: URL? = nil,
        contentType: String? = "application/json",
        upload: Bool = false,
        delegate: URLSessionTaskDelegate? = nil
    ) async throws -> Data {
        var components = URLComponents(string: "https://www.googleapis.com/\(upload ? "upload/" : "")drive/v3/\(path)")!
        components.queryItems = query
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await unavailable { try GoogleDriveAuth.shared.getAccessToken() })", forHTTPHeaderField: "Authorization")
        return try await performRequest(request, bodyFile: bodyFile, delegate: delegate)
    }
    
    private func isTransient(_ request: URLRequest, status: Int, error: [String: Any]?) -> Bool {
        let reason = (error?["errors"] as? [[String: Any]])?.first?["reason"] as? String
        let limited = status == 429 || (status == 403 && reason?.hasSuffix("ateLimitExceeded") == true)
        return limited || (status >= 500 && request.httpMethod != "POST")
    }
    
    func performRequest(_ request: URLRequest, bodyFile: URL? = nil, retry: Bool = true, delegate: URLSessionTaskDelegate? = nil, attempt: Int = 0) async throws -> Data {
        if isStopped {
            throw URLError(.cancelled)
        }
        if pathMonitor.currentPath.status == .unsatisfied {
            throw GoogleDriveError.unavailable(URLError(.notConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "No Internet connection."]))
        }
        
        let connection = connectionId
        var request = request
        request.timeoutInterval = UserConfig.shared.syncProvider == .ttu ? 10 : 60
        let (data, response) = try await limited {
            try await unavailable {
                if let bodyFile {
                    try await session.upload(for: request, fromFile: bodyFile, delegate: delegate)
                } else {
                    try await session.data(for: request, delegate: delegate)
                }
            }
        }
        
        try checkConnection(connection)
        try Task.checkCancellation()
        
        guard let httpResponse = response as? HTTPURLResponse else { throw GoogleDriveError.invalidResponse }
        if httpResponse.statusCode == 401 && retry {
            let newToken = try await unavailable { try await GoogleDriveAuth.shared.refreshAccessToken() }
            try checkConnection(connection)
            try Task.checkCancellation()
            var newRequest = request
            newRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await performRequest(newRequest, bodyFile: bodyFile, retry: false, delegate: delegate, attempt: attempt)
        }
        if httpResponse.statusCode >= 400 {
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            if attempt < 4, isTransient(request, status: httpResponse.statusCode, error: error) {
                try await Task.sleep(for: .seconds(pow(2, Double(attempt)) + Double.random(in: 0..<1)))
                try checkConnection(connection)
                return try await performRequest(request, bodyFile: bodyFile, retry: retry, delegate: delegate, attempt: attempt + 1)
            }
            if let message = error?["message"] as? String {
                throw GoogleDriveError.apiError(message, statusCode: httpResponse.statusCode)
            }
            
            throw GoogleDriveError.apiError("Request failed with status \(httpResponse.statusCode)", statusCode: httpResponse.statusCode)
        }
        
        return data
    }
    
    private func limited<T>(_ operation: () async throws -> T) async throws -> T {
        if active < 8 {
            active += 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
        defer {
            if waiting.isEmpty {
                active -= 1
            } else {
                waiting.removeFirst().resume()
            }
        }
        return try await operation()
    }
    
    private func unavailable<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            throw GoogleDriveError.unavailable(error)
        }
    }
    
    @discardableResult
    func write(data: Data, name: String, parent: String, fileId: String? = nil, contentType: String = "application/octet-stream") async throws -> GoogleDriveFile {
        let boundary = UUID().uuidString
        var body = try multipartPrefix(boundary: boundary, name: name, parent: parent, fileId: fileId, contentType: contentType)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try await write(fileId: fileId, boundary: boundary, body: body)
    }
    
    @discardableResult
    func write(file: URL, name: String, parent: String, contentType: String = "application/octet-stream") async throws -> GoogleDriveFile {
        let boundary = UUID().uuidString
        let prefix = try multipartPrefix(boundary: boundary, name: name, parent: parent, fileId: nil, contentType: contentType)
        let bodyFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: bodyFile) }
        try await Task.detached {
            try prefix.write(to: bodyFile)
            let output = try FileHandle(forWritingTo: bodyFile)
            defer { try? output.close() }
            try output.seekToEnd()
            try output.write(contentsOf: Data(contentsOf: file, options: .alwaysMapped))
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        }.value
        return try await write(fileId: nil, boundary: boundary, bodyFile: bodyFile)
    }
    
    private func multipartPrefix(boundary: String, name: String, parent: String, fileId: String?, contentType: String) throws -> Data {
        var metadata: [String: Any] = ["name": name]
        if fileId == nil {
            metadata["parents"] = [parent]
        }
        var prefix = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        prefix.append(try JSONSerialization.data(withJSONObject: metadata))
        prefix.append(Data("\r\n--\(boundary)\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        return prefix
    }
    
    private func write(fileId: String?, boundary: String, body: Data? = nil, bodyFile: URL? = nil) async throws -> GoogleDriveFile {
        let response = try await request(
            fileId.map { "files/\($0)" } ?? "files",
            query: [URLQueryItem(name: "uploadType", value: "multipart"), URLQueryItem(name: "fields", value: "id,name,mimeType,md5Checksum,createdTime")],
            method: fileId == nil ? "POST" : "PATCH",
            body: body,
            bodyFile: bodyFile,
            contentType: "multipart/related; boundary=\(boundary)",
            upload: true
        )
        return try JSONDecoder().decode(GoogleDriveFile.self, from: response)
    }
    
    func downloadFile(fileId: String, fileSize: Int64, onProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws -> Data {
        try await request(
            "files/\(fileId)",
            query: [URLQueryItem(name: "alt", value: "media")],
            contentType: nil,
            delegate: DownloadProgress(fileSize: fileSize, onProgress: onProgress)
        )
    }
    
    func trashFile(fileId: String) async throws {
        _ = try await request(
            "files/\(fileId)",
            method: "PATCH",
            body: JSONSerialization.data(withJSONObject: ["trashed": true])
        )
    }
}

nonisolated private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let fileSize: Int64
    let onProgress: @MainActor @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    
    init(fileSize: Int64, onProgress: @MainActor @Sendable @escaping (Double) -> Void) {
        self.fileSize = fileSize
        self.onProgress = onProgress
    }
    
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.observe(\.countOfBytesReceived) { [fileSize, onProgress] task, _ in
            guard fileSize > 0 else { return }
            let progress = Double(task.countOfBytesReceived) / Double(fileSize)
            Task { @MainActor in
                onProgress(progress)
            }
        }
    }
}
