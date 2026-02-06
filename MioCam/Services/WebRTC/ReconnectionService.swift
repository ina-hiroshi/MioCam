//
//  ReconnectionService.swift
//  MioCam
//
//  WebRTC接続の自動再接続を管理するサービス
//

import Foundation
import Combine

/// 再接続状態
enum ReconnectionState {
    case idle
    case reconnecting(attempt: Int)
    case connected
    case failed
}

/// 再接続サービスのデリゲートプロトコル
protocol ReconnectionServiceDelegate: AnyObject {
    /// 再接続状態が変化した時
    func reconnectionService(_ service: ReconnectionService, didChangeState state: ReconnectionState, for sessionId: String)
    /// 再接続を実行する時（デリゲートが実際の再接続処理を行う）
    func reconnectionService(_ service: ReconnectionService, shouldReconnect sessionId: String) async throws
}

/// 指数バックオフによる自動再接続を管理するサービス
class ReconnectionService {
    static let shared = ReconnectionService()
    
    weak var delegate: ReconnectionServiceDelegate?
    
    // MARK: - Configuration
    
    /// 最大再接続試行回数
    let maxAttempts = 5
    
    /// 基本の待機時間（秒）
    let baseDelay: TimeInterval = 1.0
    
    /// 最大待機時間（秒）
    let maxDelay: TimeInterval = 16.0
    
    // MARK: - Properties
    
    /// アクティブな再接続タスク（sessionId -> Task）
    private var reconnectionTasks: [String: Task<Void, Never>] = [:]
    
    /// 現在の再接続状態（sessionId -> state）
    private var states: [String: ReconnectionState] = [:]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 再接続を開始
    func startReconnection(for sessionId: String) {
        // 既存のタスクをキャンセル
        cancelReconnection(for: sessionId)
        
        // 新しい再接続タスクを開始
        let task = Task {
            await performReconnection(for: sessionId)
        }
        
        reconnectionTasks[sessionId] = task
    }
    
    /// 再接続をキャンセル
    func cancelReconnection(for sessionId: String) {
        reconnectionTasks[sessionId]?.cancel()
        reconnectionTasks.removeValue(forKey: sessionId)
        states.removeValue(forKey: sessionId)
    }
    
    /// すべての再接続をキャンセル
    func cancelAllReconnections() {
        for (sessionId, task) in reconnectionTasks {
            task.cancel()
            reconnectionTasks.removeValue(forKey: sessionId)
        }
        states.removeAll()
    }
    
    /// 接続成功を通知（再接続タスクを停止）
    func connectionSucceeded(for sessionId: String) {
        cancelReconnection(for: sessionId)
        updateState(.connected, for: sessionId)
    }
    
    /// 現在の再接続状態を取得
    func state(for sessionId: String) -> ReconnectionState {
        return states[sessionId] ?? .idle
    }
    
    // MARK: - Private Methods
    
    private func performReconnection(for sessionId: String) async {
        var attempt = 0
        
        while attempt < maxAttempts && !Task.isCancelled {
            attempt += 1
            
            // 状態を更新
            updateState(.reconnecting(attempt: attempt), for: sessionId)
            
            // 待機時間を計算（指数バックオフ）
            let delay = calculateDelay(for: attempt)
            print("ReconnectionService: セッション \(sessionId) の再接続試行 \(attempt)/\(maxAttempts)、待機時間: \(delay)秒")
            
            // 待機
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                // キャンセルされた
                print("ReconnectionService: セッション \(sessionId) の再接続がキャンセルされました")
                return
            }
            
            // 再接続を試行
            do {
                try await delegate?.reconnectionService(self, shouldReconnect: sessionId)
                
                // 成功
                updateState(.connected, for: sessionId)
                print("ReconnectionService: セッション \(sessionId) の再接続に成功しました")
                return
            } catch {
                print("ReconnectionService: セッション \(sessionId) の再接続に失敗しました - \(error.localizedDescription)")
                
                if attempt >= maxAttempts {
                    // 最大試行回数に達した
                    updateState(.failed, for: sessionId)
                    print("ReconnectionService: セッション \(sessionId) の再接続が失敗しました（最大試行回数超過）")
                }
            }
        }
    }
    
    /// 指数バックオフで待機時間を計算（1s → 2s → 4s → 8s → 16s）
    private func calculateDelay(for attempt: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        return min(exponentialDelay, maxDelay)
    }
    
    private func updateState(_ state: ReconnectionState, for sessionId: String) {
        states[sessionId] = state
        
        Task { @MainActor in
            delegate?.reconnectionService(self, didChangeState: state, for: sessionId)
        }
    }
}

// MARK: - Network Monitoring

import Network

/// ネットワーク接続監視
class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.miocam.networkmonitor")
    
    /// ネットワークが利用可能かどうか
    @Published private(set) var isConnected = true
    
    /// 接続タイプ
    @Published private(set) var connectionType: ConnectionType = .unknown
    
    enum ConnectionType {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
    }
    
    private init() {}
    
    /// 監視を開始
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.updateConnectionType(path)
            }
        }
        monitor.start(queue: queue)
    }
    
    /// 監視を停止
    func stop() {
        monitor.cancel()
    }
    
    private func updateConnectionType(_ path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = .unknown
        }
    }
}
