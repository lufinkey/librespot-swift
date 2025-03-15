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
						let session = try await Librespot.authenticate()
						NSLog("Session \(session?.accessToken)");
					} catch let error {
						NSLog("\(error.localizedDescription)")
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
