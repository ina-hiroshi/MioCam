//
//  MioCamWatchApp.swift
//  MioCamWatch
//
//  Created on 2026-02-07.
//

import SwiftUI

@main
struct MioCamWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// メインコンテンツビュー
struct ContentView: View {
    var body: some View {
        NavigationStack {
            CameraStatusListView()
        }
    }
}
