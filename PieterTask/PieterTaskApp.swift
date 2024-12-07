//
//  PieterTaskApp.swift
//  PieterTask
//
//  Created by Pieter Yoshua Natanael on 06/12/24.
//

import SwiftUI

@main
struct PieterTaskApp: App {
    @StateObject private var playlistStore = PlaylistStore()
    
    var body: some Scene {
        WindowGroup {
            MainAppView()
        }
    }
}
