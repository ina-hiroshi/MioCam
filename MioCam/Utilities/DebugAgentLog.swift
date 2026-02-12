//
//  DebugAgentLog.swift
//  MioCam
//
//  デバッグセッション用ログ送信（instrumentation）
//

import Foundation

/// 映像不具合デバッグ用。NDJSONをDocuments/video_debug.logに追記し、[DBG]付きでprint。
func videoBugLog(location: String, message: String, data: [String: Any] = [:], hypothesisId: String? = nil) {
    #if DEBUG
    var payload: [String: Any] = [
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    if let h = hypothesisId { payload["hypothesisId"] = h }
    guard let body = try? JSONSerialization.data(withJSONObject: payload),
          let line = String(data: body, encoding: .utf8) else { return }
    let logLine = line + "\n"
    let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("video_debug.log")
    if FileManager.default.fileExists(atPath: logURL.path) {
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(logLine.data(using: .utf8)!)
            try? handle.close()
        }
    } else {
        try? logLine.write(to: logURL, atomically: false, encoding: .utf8)
    }
    print("[DBG] \(line)")
    #endif
}

// #region agent log
/// デバッグエージェント用ログ送信。DEBUGビルドかつデバッグサーバ未起動時はConnection refusedが発生するため無効化。
func agentLog(location: String, message: String, data: [String: Any] = [:], hypothesisId: String? = nil) {
    #if DEBUG
    // 環境変数 AGENT_LOG_ENABLED=1 が設定されている場合のみ送信（デバッグサーバ起動時）
    guard ProcessInfo.processInfo.environment["AGENT_LOG_ENABLED"] == "1" else { return }
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
    #endif
}
// #endregion agent log
