//
//  GoogleDriveAuth.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AuthenticationServices

enum GoogleDriveAuthError: LocalizedError {
    case invalidAuthURL
    case noCallbackURL
    case missingAuthorizationCode
    case tokenExchangeFailed(statusCode: Int)
    case notAuthenticated
    case tokenRefreshFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAuthURL:
            return "Failed to construct authentication URL"
        case .noCallbackURL:
            return "No callback URL received"
        case .missingAuthorizationCode:
            return "Authorization code missing from callback"
        case .tokenExchangeFailed(let statusCode):
            return "Token exchange failed: \(statusCode)"
        case .notAuthenticated:
            return "Not authenticated\nPlease sign in"
        case .tokenRefreshFailed:
            return "Failed to refresh token\nPlease sign in again"
        }
    }
}

@MainActor
@Observable
class GoogleDriveAuth: NSObject {
    static let shared = GoogleDriveAuth()
    private override init() {}
    
    var isAuthenticated: Bool {
        TokenStorage.get("accessToken") != nil
    }

    func getAccessToken() throws -> String {
        guard let token = TokenStorage.get("accessToken") else {
            throw GoogleDriveAuthError.notAuthenticated
        }
        return token
    }

    func authenticate(clientId: String) async throws {
        let scheme = clientId.components(separatedBy: ".").reversed().joined(separator: ".")
        let redirectUri = "\(scheme):/oauth2callback"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
        ]

        guard let authURL = components.url else {
            throw GoogleDriveAuthError.invalidAuthURL
        }

        let code = try await getAuthorizationCode(from: authURL, callbackScheme: scheme)
        try await exchangeCode(code: code, clientId: clientId, redirectUri: redirectUri)
        TokenStorage.save(clientId, for: "clientId")
    }
    
    func refreshAccessToken() async throws -> String {
        guard let refreshToken = TokenStorage.get("refreshToken"),
              let clientId = TokenStorage.get("clientId") else {
            throw GoogleDriveAuthError.notAuthenticated
        }

        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            TokenStorage.clear()
            throw GoogleDriveAuthError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        TokenStorage.save(tokenResponse.accessToken, for: "accessToken")
        
        return tokenResponse.accessToken
    }
    
    private func getAuthorizationCode(from url: URL, callbackScheme: String) async throws -> String {
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleDriveAuthError.noCallbackURL)
                }
            }
            
            session.presentationContextProvider = self
            session.start()
        }
        
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleDriveAuthError.missingAuthorizationCode
        }
        
        return code
    }
    
    private func exchangeCode(code: String, clientId: String, redirectUri: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GoogleDriveAuthError.tokenExchangeFailed(statusCode: statusCode)
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        TokenStorage.save(tokenResponse.accessToken, for: "accessToken")
        if let refresh = tokenResponse.refreshToken {
            TokenStorage.save(refresh, for: "refreshToken")
        }
    }
}

extension GoogleDriveAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first!
        return windowScene.keyWindow ?? UIWindow(windowScene: windowScene)
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
