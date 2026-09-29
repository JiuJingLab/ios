import Foundation

struct DetectionRules: Decodable {
    let version: Int
    let nameKeywords: [String]
    let ports: [UInt16]
    let videoPorts: [UInt16]

    static func load(bundle: Bundle = .main) throws -> DetectionRules {
        guard let url = bundle.url(forResource: "known_cameras", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let rules = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard !rules.ports.isEmpty, rules.ports.allSatisfy({ $0 > 0 }),
              Set(rules.videoPorts).isSubset(of: Set(rules.ports)),
              rules.nameKeywords.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return rules
    }

    func reasons(name: String, ports: Set<UInt16> = [], services: Set<String> = []) -> [String] {
        var result: [String] = []
        let services = Set(services.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        if let keyword = nameKeywords.first(where: { name.localizedCaseInsensitiveContains($0) }) {
            result.append("名稱含有「\(keyword)」；裝置名稱可自行更改，需人工確認。")
        }
        if !ports.intersection(Set(videoPorts)).isEmpty || services.contains("_rtsp._tcp") {
            result.append("提供可能用於影像串流的 RTSP 服務；也可能是合法設備。")
        }
        if services.contains("_axis-video._tcp") {
            result.append("廣播影像相關 Bonjour 服務，建議確認設備用途。")
        }
        return result
    }
}

struct Finding: Identifiable {
    enum Source: String { case network = "區域網路", bluetooth = "藍牙 BLE" }
    let id: String
    var name: String
    let source: Source
    var address: String
    var ports: Set<UInt16> = []
    var services: Set<String> = []
    var rssi: Int?
    var reasons: [String] = []
    var needsReview: Bool { !reasons.isEmpty }
}

struct IPv4Subnet {
    let address: UInt32
    let mask: UInt32

    init?(address: String, mask: String) {
        guard let ip = Self.number(address), let netmask = Self.number(mask) else { return nil }
        let inverse = ~netmask
        guard inverse & (inverse &+ 1) == 0, netmask != 0 else { return nil }
        self.address = ip
        self.mask = netmask
    }
    static func number(_ value: String) -> UInt32? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let octet = UInt8(part) else { return nil }
            result = result << 8 | UInt32(octet)
        }
        return result
    }
    static func string(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> $0) & 255) }.joined(separator: ".")
    }
    var isPartial: Bool { mask < 0xffffff00 }
    var label: String { "\(Self.string(address & mask))/\(mask.nonzeroBitCount)" }
    var hosts: [String] {
        // Bound large LANs to the phone's /24 window; never leave the actual subnet.
        let low = max(address & mask, address & 0xffffff00)
        let high = min((address & mask) | ~mask, (address & 0xffffff00) | 255)
        let network = address & mask
        let broadcast = network | ~mask
        guard low < high else { return [] }
        return (low...high).filter { $0 != address && $0 != network && $0 != broadcast }.map(Self.string)
    }
}
