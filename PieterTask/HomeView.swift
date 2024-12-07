//
//  LibraryView.swift
//  PieterTask
//
//  Created by Pieter Yoshua Natanael on 07/12/24.
//

// ContentView.swift

import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack {
            Image(systemName: "slowmo")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Under maintenance!")
        }
        .padding()
    }
}

#Preview {
    HomeView()
}
 
