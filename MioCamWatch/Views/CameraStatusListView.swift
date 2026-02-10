//
//  CameraStatusListView.swift
//  MioCamWatch
//
//  Created on 2026-02-07.
//

import SwiftUI

/// カメラステータス一覧画面（Watch用）
struct CameraStatusListView: View {
    @State private var cameras: [CameraStatus] = []
    @State private var isLoading = true
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("読み込み中...")
            } else if cameras.isEmpty {
                Text("ペアリング済みのカメラがありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(cameras) { camera in
                    NavigationLink {
                        CameraDetailView(camera: camera)
                    } label: {
                        CameraStatusRow(camera: camera)
                    }
                }
            }
        }
        .navigationTitle("MioCam")
        .task {
            await loadCameras()
        }
    }
    
    private func loadCameras() async {
        // TODO: iOSアプリと共有するデータを読み込む
        // WatchConnectivityまたはFirebaseを使用
        isLoading = false
    }
}

/// カメラステータス行
struct CameraStatusRow: View {
    let camera: CameraStatus
    
    var body: some View {
        HStack {
            Circle()
                .fill(camera.isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.name)
                    .font(.headline)
                
                if let battery = camera.batteryLevel {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(level: battery))
                            .font(.caption2)
                        Text("\(battery)%")
                            .font(.caption2)
                    }
                    .foregroundColor(batteryColor(level: battery))
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func batteryIcon(level: Int) -> String {
        switch level {
        case 0..<10: return "battery.0"
        case 10..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func batteryColor(level: Int) -> Color {
        switch level {
        case 0..<10: return .red
        case 10..<20: return .orange
        default: return .primary
        }
    }
}

/// カメラ詳細画面
struct CameraDetailView: View {
    let camera: CameraStatus
    
    var body: some View {
        List {
            Section("ステータス") {
                HStack {
                    Text("接続状態")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(camera.isOnline ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(camera.isOnline ? "オンライン" : "オフライン")
                            .font(.caption)
                    }
                }
                
                if let battery = camera.batteryLevel {
                    HStack {
                        Text("バッテリー")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon(level: battery))
                            Text("\(battery)%")
                        }
                        .font(.caption)
                        .foregroundColor(batteryColor(level: battery))
                    }
                }
            }
        }
        .navigationTitle(camera.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func batteryIcon(level: Int) -> String {
        switch level {
        case 0..<10: return "battery.0"
        case 10..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func batteryColor(level: Int) -> Color {
        switch level {
        case 0..<10: return .red
        case 10..<20: return .orange
        default: return .primary
        }
    }
}

/// カメラステータスモデル（Watch用簡易版）
struct CameraStatus: Identifiable {
    let id: String
    let name: String
    let isOnline: Bool
    let batteryLevel: Int?
}
