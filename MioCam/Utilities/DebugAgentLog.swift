//
//  DebugAgentLog.swift
//  MioCam
//
//  デバッグセッション用ログ送信（instrumentation）
//

import Foundation

// #region agent log
func agentLog(location: String, message: String, data: [String: Any] = [:], hypothesisId: String? = nil) {
    var payload: [String: Any] = [
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    if let h = hypothesisId { payload["hypothesisId"] = h }
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
    var req = URLRequest(url: URL(string: "http://127.0.0.1:7244/ingest/74574eb4-aa15-41a9-8645-bcfddd404b52")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = body
    URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
}
// #endregion agent log
