import Foundation
import Network

enum GoogleDriveError: LocalizedError {
    case invalidResponse
    case apiError(String, statusCode: Int?)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Invalid response from Google Drive")
        case .apiError(let message, _):
            return message
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
        contentType: String? = "application/json",
        upload: Bool = false,
        delegate: URLSessionTaskDelegate? = nil
    ) async throws -> Data {
        var components = URLComponents(string: "https://www.googleapis.com/\(upload ? "upload/" : "")drive/v3/\(path)")!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try GoogleDriveAuth.shared.getAccessToken())", forHTTPHeaderField: "Authorization")
        return try await performRequest(request, delegate: delegate)
    }
    
    func performRequest(_ request: URLRequest, retry: Bool = true, delegate: URLSessionTaskDelegate? = nil) async throws -> Data {
        if isStopped {
            throw URLError(.cancelled)
        }
        if pathMonitor.currentPath.status == .unsatisfied {
            throw URLError(.notConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "No Internet connection."])
        }
        
        let connection = connectionId
        var request = request
        request.timeoutInterval = UserConfig.shared.syncProvider == .ttu ? 10 : 60
        let (data, response) = try await session.data(for: request, delegate: delegate)
        
        try checkConnection(connection)
        try Task.checkCancellation()
        
        guard let httpResponse = response as? HTTPURLResponse else { throw GoogleDriveError.invalidResponse }
        if httpResponse.statusCode == 401 && retry {
            let newToken = try await GoogleDriveAuth.shared.refreshAccessToken()
            try checkConnection(connection)
            try Task.checkCancellation()
            var newRequest = request
            newRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await performRequest(newRequest, retry: false, delegate: delegate)
        }
        if httpResponse.statusCode >= 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let error = errorJson["error"] as? [String: Any],
                let message = error["message"] as? String {
                throw GoogleDriveError.apiError(message, statusCode: httpResponse.statusCode)
            }
            
            throw GoogleDriveError.apiError("Request failed with status \(httpResponse.statusCode)", statusCode: httpResponse.statusCode)
        }
        
        return data
    }
    
    @discardableResult
    func write(data: Data, name: String, parent: String, fileId: String? = nil, contentType: String = "application/octet-stream") async throws -> GoogleDriveFile {
        var metadata: [String: Any] = ["name": name]
        if fileId == nil {
            metadata["parents"] = [parent]
        }
        let boundary = UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let response = try await request(
            fileId.map { "files/\($0)" } ?? "files",
            query: [URLQueryItem(name: "uploadType", value: "multipart"), URLQueryItem(name: "fields", value: "id,name,mimeType,version,createdTime")],
            method: fileId == nil ? "POST" : "PATCH",
            body: body,
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
