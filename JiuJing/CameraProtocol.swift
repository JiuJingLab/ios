import Foundation

enum VerificationError: Error, LocalizedError {
    case invalidTarget, malformed, tooLarge, unsupported
    var errorDescription: String? {
        switch self {
        case .invalidTarget: return "請輸入同一 Wi-Fi 的 http:// 或 rtsp:// 私有 IPv4 網址，不含帳密或片段。"
        case .malformed: return "裝置回應格式不完整或不合法，無法確認。"
        case .tooLarge: return "回應超過安全處理上限，已停止驗證。"
        case .unsupported: return "目前只支援 RTSP 1.0 描述、HTTP JPEG 與 MJPEG；此回應不支援。"
        }
    }
}

struct CameraTarget {
    let host: String
    let port: UInt16
    let path: String
    let isRTSP: Bool
    var address: String { "\(isRTSP ? "rtsp" : "http")://\(host):\(port)\(path)" }

    init(_ text: String) throws {
        guard text.utf8.count <= 2048,
              let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "rtsp"].contains(scheme),
              let host = parts.host, let ip = IPv4Subnet.number(host),
              Self.isPrivate(ip), host == IPv4Subnet.string(ip),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let port = UInt16(exactly: parts.port ?? (scheme == "rtsp" ? 554 : 80)), port > 0 else {
            throw VerificationError.invalidTarget
        }
        self.host = host; self.port = port; isRTSP = scheme == "rtsp"
        path = (parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath) + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
    static func isPrivate(_ ip: UInt32) -> Bool {
        ip & 0xff000000 == 0x0a000000 || ip & 0xfff00000 == 0xac100000 || ip & 0xffff0000 == 0xc0a80000
    }
    func isOn(_ subnet: IPv4Subnet) -> Bool {
        guard let ip = IPv4Subnet.number(host) else { return false }
        let network = subnet.address & subnet.mask
        return ip & subnet.mask == network && ip != subnet.address && ip != network && ip != (network | ~subnet.mask)
    }
    var request: Data {
        let request = isRTSP
            ? "DESCRIBE \(address) RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\nUser-Agent: JiuJing/0.3\r\n\r\n"
            : "GET \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nAccept: image/jpeg, multipart/x-mixed-replace\r\nAccept-Encoding: identity\r\nCache-Control: no-cache\r\nConnection: close\r\nUser-Agent: JiuJing/0.3\r\n\r\n"
        return Data(request.utf8)
    }
}

struct CameraResponseHead {
    let status: Int
    let fields: [String: String]
    init(_ data: Data, rtsp: Bool) throws {
        guard data.count <= 16384, let text = String(data: data, encoding: .utf8) else { throw VerificationError.malformed }
        let lines = text.components(separatedBy: "\r\n")
        let status = (lines.first ?? "").split(separator: " ")
        guard status.count >= 2, (rtsp ? ["RTSP/1.0"] : ["HTTP/1.0", "HTTP/1.1"]).contains(String(status[0])),
              let code = Int(status[1]), (100...599).contains(code) else { throw VerificationError.malformed }
        self.status = code
        fields = try Self.headers(Array(lines.dropFirst()))
        if rtsp, fields["cseq"] != "1" { throw VerificationError.malformed }
        if fields["content-length"] != nil && fields["transfer-encoding"] != nil { throw VerificationError.malformed }
    }
    static func headers(_ lines: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { throw VerificationError.malformed }
            let key = line[..<colon].lowercased()
            guard !key.isEmpty, result[key] == nil else { throw VerificationError.malformed }
            result[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }
    static func length(_ text: String?, limit: Int) throws -> Int? {
        guard let text else { return nil }
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let count = Int(text) else { throw VerificationError.malformed }
        guard count <= limit else { throw VerificationError.tooLarge }
        return count
    }
    var mediaType: String { (fields["content-type"] ?? "").components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces).lowercased() }
    var boundary: String? {
        for parameter in (fields["content-type"] ?? "").components(separatedBy: ";").dropFirst() {
            let parts = parameter.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "boundary" {
                let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if (1...70).contains(value.utf8.count), value.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) { return value }
            }
        }
        return nil
    }
}

struct HTTPChunks {
    private var buffer = Data()
    private var remaining: Int?
    private(set) var finished = false
    mutating func feed(_ data: Data) throws -> Data {
        guard !finished else { return Data() }
        buffer.append(data)
        guard buffer.count <= 2_200_000 else { throw VerificationError.tooLarge }
        var result = Data()
        while !finished {
            if remaining == nil {
                guard let line = buffer.range(of: Data("\r\n".utf8)) else {
                    if buffer.count > 128 { throw VerificationError.malformed }; break
                }
                guard line.lowerBound - buffer.startIndex <= 128,
                      let text = String(data: buffer[..<line.lowerBound], encoding: .ascii),
                      let token = text.split(separator: ";", maxSplits: 1).first,
                      !token.isEmpty, token.allSatisfy(\.isHexDigit), let count = Int(token, radix: 16), count <= 2_097_152 else {
                    throw VerificationError.malformed
                }
                buffer.removeSubrange(..<line.upperBound)
                if count == 0 { finished = true; break }
                remaining = count
            }
            guard let count = remaining, buffer.count >= count + 2 else { break }
            let end = buffer.index(buffer.startIndex, offsetBy: count)
            guard buffer[end..<buffer.index(end, offsetBy: 2)] == Data("\r\n".utf8) else { throw VerificationError.malformed }
            result.append(buffer[..<end]); buffer.removeSubrange(..<buffer.index(end, offsetBy: 2)); remaining = nil
        }
        return result
    }
}

struct MJPEGFrames {
    static let maxFrame = 2_097_152
    private let delimiter: Data
    private var buffer = Data()
    private var readingHeaders = false
    private var readingBody = false
    private var length: Int?
    private(set) var finished = false
    init(boundary: String) { delimiter = Data(("--" + boundary).utf8) }
    mutating func feed(_ data: Data) throws -> [Data] {
        guard !finished else { return [] }
        buffer.append(data)
        guard buffer.count <= Self.maxFrame + 65536 else { throw VerificationError.tooLarge }
        var frames: [Data] = []
        while !finished {
            if !readingBody && !readingHeaders {
                guard let range = buffer.range(of: delimiter) else {
                    if buffer.count > 16384 { throw VerificationError.malformed }; break
                }
                guard buffer.distance(from: range.upperBound, to: buffer.endIndex) >= 2 else { break }
                let suffix = buffer[range.upperBound..<buffer.index(range.upperBound, offsetBy: 2)]
                if suffix == Data("--".utf8) { finished = true; break }
                guard suffix == Data("\r\n".utf8) else { throw VerificationError.malformed }
                buffer.removeSubrange(..<buffer.index(range.upperBound, offsetBy: 2)); readingHeaders = true
            }
            if readingHeaders {
                guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    if buffer.count > 16384 { throw VerificationError.malformed }; break
                }
                guard buffer.distance(from: buffer.startIndex, to: range.lowerBound) <= 16384,
                      let text = String(data: buffer[..<range.lowerBound], encoding: .utf8) else { throw VerificationError.malformed }
                let headers = try CameraResponseHead.headers(text.components(separatedBy: "\r\n"))
                guard headers["content-type"]?.lowercased() == "image/jpeg" else { throw VerificationError.unsupported }
                length = try CameraResponseHead.length(headers["content-length"], limit: Self.maxFrame)
                buffer.removeSubrange(..<range.upperBound); readingHeaders = false; readingBody = true
            }
            if readingBody {
                let end: Data.Index
                if let length {
                    guard buffer.count >= length else { break }
                    end = buffer.index(buffer.startIndex, offsetBy: length)
                } else {
                    guard let range = buffer.range(of: Data("\r\n".utf8) + delimiter) else { break }
                    end = range.lowerBound
                }
                guard buffer.distance(from: buffer.startIndex, to: end) <= Self.maxFrame else { throw VerificationError.tooLarge }
                frames.append(Data(buffer[..<end])); buffer.removeSubrange(..<end); readingBody = false
            }
        }
        return frames
    }
}

enum VideoDescription {
    static func hasVideo(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.first == "v=0", lines.contains(where: { $0.hasPrefix("o=") }),
              lines.contains(where: { $0.hasPrefix("s=") }), lines.contains(where: { $0.hasPrefix("t=") }) else { return false }
        return lines.contains { line in
            let parts = line.split(separator: " ")
            guard parts.count >= 4, parts[0] == "m=video",
                  UInt16(parts[1].split(separator: "/").first ?? "") != nil else { return false }
            return parts[2] == "RTP/AVP" || parts[2] == "RTP/AVP/TCP" || parts[2] == "RTP/SAVP"
        }
    }
}
