import Foundation

/// Where the widget lives on the network, plus the shared secret from its
/// pairing URL.
struct ServerConfig: Codable, Equatable {
    /// Every address the Mac answers on, as "scheme://host[:port]", best
    /// first: the public tunnel, home Wi-Fi, Tailscale. The first is the last
    /// one that worked.
    var endpoints: [String]
    var key: String

    init(endpoints: [String], key: String) {
        self.endpoints = endpoints
        self.key = key
    }

    /// What Settings shows: the working address without its scheme.
    var host: String {
        guard let first = endpoints.first, let comps = URLComponents(string: first) else { return "—" }
        return [comps.host, comps.port.map(String.init)].compactMap { $0 }.joined(separator: ":")
    }

    func url(_ path: String, query: [String: String] = [:], base: String? = nil) -> URL? {
        guard let base = base ?? endpoints.first,
              var comps = URLComponents(string: base + path) else { return nil }
        var items = [URLQueryItem(name: "key", value: key)]
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items
        return comps.url
    }

    /// Accepts the pairing URL straight from the widget or the QR code, e.g.
    /// https://tasks.example.com/?key=abc123 or http://10.0.0.5:43917/?key=abc123
    static func parse(_ raw: String) -> ServerConfig? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let comps = URLComponents(string: withScheme),
              let scheme = comps.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = comps.host,
              let key = comps.queryItems?.first(where: { $0.name == "key" })?.value,
              !key.isEmpty
        else { return nil }
        // A tunnel serves https on its own port; a bare Mac address is the widget's.
        let port = comps.port ?? (scheme == "http" ? 43917 : nil)
        let base = "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
        return ServerConfig(endpoints: [base], key: key)
    }

    // Configs saved before multi-address support hold a single "host:port".
    private enum CodingKeys: String, CodingKey { case endpoints, key, host }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        if let list = try c.decodeIfPresent([String].self, forKey: .endpoints), !list.isEmpty {
            endpoints = list
        } else {
            endpoints = ["http://" + (try c.decode(String.self, forKey: .host))]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(endpoints, forKey: .endpoints)
        try c.encode(key, forKey: .key)
    }
}
