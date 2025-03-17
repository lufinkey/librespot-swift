//
//  ContentView.swift
//  LibrespotSwiftExample
//
//  Created by Luis Finke on 3/15/25.
//

import SwiftUI
import LibrespotSwift

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
			Button("Login") {
				Task {
					do {
						let session = try await LibrespotShared.shared.login()
						NSLog("Session \(session)");
					} catch let error {
						NSLog("Failed to login: \(error.localizedDescription)")
					}
				}
			}
			
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
