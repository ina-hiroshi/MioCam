//
//  MioCamApp.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI
import FirebaseCore

@main
struct MioCamApp: App {
    init() {
        // Firebase初期化
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// プレースホルダー: 後で実装
struct ContentView: View {
    var body: some View {
        Text("MioCam")
            .font(.system(.largeTitle, design: .rounded))
    }
}
