import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SyncDecision: Equatable {
    case noChange
    case push
    case pull
    case conflict
}

public enum SyncPlanner {
    public static func decide(base: String, local: String, remote: String) -> SyncDecision {
        let baseValue = normalize(base)
        let localValue = normalize(local)
        let remoteValue = normalize(remote)

        if localValue == remoteValue { return .noChange }
        if remoteValue == baseValue { return .push }
        if localValue == baseValue { return .pull }
        return .conflict
    }

    private static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum NotionError: Error, Equatable, CustomStringConvertible {
    case invalidPageID
    case invalidResponse
    case truncatedContent
    case http(status: Int, retryAfter: Int?)
    case api(code: String, message: String)
    case transport(String)

    public var description: String {
        switch self {
        case .invalidPageID:
            return "Notion 页面 ID 无效"
        case .invalidResponse:
            return "Notion 返回了无法解析的响应"
        case .truncatedContent:
            return "Notion 页面过大，已停止同步以避免覆盖未读取内容"
        case let .http(status, retryAfter):
            if let retryAfter = retryAfter {
                return "Notion 请求失败（HTTP \(status)，\(retryAfter) 秒后可重试）"
            }
            return "Notion 请求失败（HTTP \(status)）"
        case let .api(code, message):
            switch code {
            case "unauthorized": return "Notion Token 无效"
            case "restricted_resource": return "Notion 集成没有所需权限"
            case "object_not_found": return "Notion 页面不存在，或尚未授权给该集成"
            case "rate_limited": return "Notion 请求过于频繁，请稍后重试"
            case "validation_error": return "Notion 拒绝了本次更新：\(message)"
            default: return message
            }
        case let .transport(message):
            return message
        }
    }
}

public protocol HTTPTransporting {
    func send(_ request: URLRequest, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void)
}

public final class URLSessionTransport: HTTPTransporting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NotionError.invalidResponse))
                return
            }
            completion(.success((data ?? Data(), http)))
        }.resume()
    }
}

public final class NotionClient {
    public static let apiVersion = "2026-03-11"
    public static let requestTimeout: TimeInterval = 15

    private let transport: HTTPTransporting
    private let baseURL: URL

    public init(transport: HTTPTransporting = URLSessionTransport(), baseURL: URL = URL(string: "https://api.notion.com")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func retrievePageMarkdown(
        pageID: String,
        token: String,
        completion: @escaping (Result<String, NotionError>) -> Void
    ) {
        guard let normalized = NotionPageID.normalize(pageID) else {
            completion(.failure(.invalidPageID))
            return
        }
        var request = URLRequest(url: endpoint(pageID: normalized))
        request.httpMethod = "GET"
        applyHeaders(to: &request, token: token)
        perform(request, rejectTruncatedContent: true, completion: completion)
    }

    public func replacePageMarkdown(
        pageID: String,
        token: String,
        markdown: String,
        completion: @escaping (Result<String, NotionError>) -> Void
    ) {
        guard let normalized = NotionPageID.normalize(pageID) else {
            completion(.failure(.invalidPageID))
            return
        }
        var request = URLRequest(url: endpoint(pageID: normalized))
        request.httpMethod = "PATCH"
        applyHeaders(to: &request, token: token)
        let payload: [String: Any] = [
            "type": "replace_content",
            "replace_content": [
                "new_str": markdown
            ]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(.failure(.transport("无法生成 Notion 请求")))
            return
        }
        perform(request, rejectTruncatedContent: false, completion: completion)
    }

    private func applyHeaders(to request: inout URLRequest, token: String) {
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func endpoint(pageID: String) -> URL {
        baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("pages")
            .appendingPathComponent(pageID)
            .appendingPathComponent("markdown")
    }

    private func perform(
        _ request: URLRequest,
        rejectTruncatedContent: Bool,
        completion: @escaping (Result<String, NotionError>) -> Void
    ) {
        transport.send(request) { result in
            switch result {
            case let .failure(error):
                completion(.failure((error as? NotionError) ?? .transport(error.localizedDescription)))
            case let .success((data, response)):
                guard (200..<300).contains(response.statusCode) else {
                    let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let code = json["code"] as? String,
                       let message = json["message"] as? String {
                        completion(.failure(.api(code: code, message: message)))
                    } else {
                        completion(.failure(.http(status: response.statusCode, retryAfter: retry)))
                    }
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let markdown = json["markdown"] as? String,
                      let truncated = json["truncated"] as? Bool else {
                    completion(.failure(.invalidResponse))
                    return
                }
                if rejectTruncatedContent && truncated {
                    completion(.failure(.truncatedContent))
                    return
                }
                completion(.success(markdown))
            }
        }
    }
}

public enum NotionPageID {
    public static func normalize(_ input: String) -> String? {
        let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{32})"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.matches(
                in: candidate,
                range: NSRange(candidate.startIndex..., in: candidate)
              ).last,
              let range = Range(match.range, in: candidate) else { return nil }
        let last = candidate[range].lowercased().replacingOccurrences(of: "-", with: "")
        let parts = [
            String(last.prefix(8)),
            String(last.dropFirst(8).prefix(4)),
            String(last.dropFirst(12).prefix(4)),
            String(last.dropFirst(16).prefix(4)),
            String(last.dropFirst(20).prefix(12))
        ]
        return parts.joined(separator: "-")
    }
}
