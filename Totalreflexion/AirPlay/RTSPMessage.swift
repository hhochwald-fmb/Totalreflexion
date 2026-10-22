import Foundation

/// An RTSP/1.0 or HTTP/1.1 request as sent by AirPlay clients on the control connection.
struct RTSPRequest {
    let method: String
    let path: String
    let protocolVersion: String
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var plistBody: [String: Any]? {
        guard !body.isEmpty else { return nil }
        return (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any]
    }

    /// Tries to parse one complete request from the front of `buffer`.
    /// Returns the request and the number of consumed bytes, or nil if more data is needed.
    static func parse(_ buffer: Data) -> (RTSPRequest, Int)? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return nil }
        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", maxSplits: 2).map(String.init)
        guard requestLine.count == 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.endIndex - bodyStart >= contentLength else { return nil }
        let body = Data(buffer[bodyStart..<(bodyStart + contentLength)])

        let request = RTSPRequest(method: requestLine[0], path: requestLine[1],
                                  protocolVersion: requestLine[2], headers: headers, body: body)
        return (request, bodyStart + contentLength - buffer.startIndex)
    }
}

struct RTSPResponse {
    var status = 200
    var reason = "OK"
    var headers: [(String, String)] = []
    var body = Data()
    /// Close the control connection after sending.
    var disconnect = false

    static let ok = RTSPResponse()

    static var options: RTSPResponse {
        var response = RTSPResponse()
        response.headers.append(("Public", "SETUP, RECORD, FLUSH, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER"))
        return response
    }

    static var volumeParameter: RTSPResponse {
        var response = RTSPResponse()
        response.headers.append(("Content-Type", "text/parameters"))
        response.body = Data("volume: 0.000000\r\n".utf8)
        return response
    }

    static var record: RTSPResponse {
        var response = RTSPResponse()
        response.headers.append(("Audio-Latency", "11025"))
        response.headers.append(("Audio-Jack-Status", "connected; type=analog"))
        return response
    }

    static func status(_ code: Int, _ reason: String) -> RTSPResponse {
        RTSPResponse(status: code, reason: reason)
    }

    static func plist(_ object: [String: Any]) -> RTSPResponse {
        var response = RTSPResponse()
        response.body = (try? PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0))
            ?? Data()
        response.headers.append(("Content-Type", "application/x-apple-binary-plist"))
        return response
    }

    static func binary(_ data: Data) -> RTSPResponse {
        var response = RTSPResponse()
        response.body = data
        response.headers.append(("Content-Type", "application/octet-stream"))
        return response
    }

    func serialized(for request: RTSPRequest) -> Data {
        var text = "\(request.protocolVersion) \(status) \(reason)\r\n"
        for (name, value) in headers {
            text += "\(name): \(value)\r\n"
        }
        text += "Server: AirTunes/\(AirPlayConstants.sourceVersion)\r\n"
        if let cseq = request.header("CSeq") {
            text += "CSeq: \(cseq)\r\n"
        }
        text += "Content-Length: \(body.count)\r\n\r\n"
        var data = Data(text.utf8)
        data.append(body)
        return data
    }
}
