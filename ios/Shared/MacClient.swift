import Foundation

// MARK: - Talking to the Mac

/// The few calls a widget makes. Each address gets a short timeout — a widget
/// has seconds, not minutes, to draw.
struct MacClient {
    let config: ServerConfig

    func state() async -> AppState? {
        for base in config.endpoints {
            guard let url = config.url("/api/state", base: base) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            if let (data, response) = try? await URLSession.shared.data(for: req),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let state = try? JSONDecoder().decode(AppState.self, from: data) {
                return state
            }
        }
        return nil
    }

    func complete(_ id: String, at: Double) async -> Bool {
        for base in config.endpoints {
            guard let url = config.url("/api/tasks/\(id)/toggle", base: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 5
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["done": true, "at": at])
            if let (_, response) = try? await URLSession.shared.data(for: req),
               let code = (response as? HTTPURLResponse)?.statusCode {
                // 404: the Mac already deleted it — nothing left to tick.
                return code < 400 || code == 404
            }
        }
        return false
    }

    /// Ends a focus session or a lock-in, from a Live Activity's stop button.
    func stop(_ kind: SessionKind) async -> Bool {
        let path = kind == .focus ? "/api/focus" : "/api/lockin"
        for base in config.endpoints {
            guard let url = config.url(path, base: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.timeoutInterval = 5
            if let (_, response) = try? await URLSession.shared.data(for: req),
               let code = (response as? HTTPURLResponse)?.statusCode {
                return code < 400
            }
        }
        return false
    }
}
