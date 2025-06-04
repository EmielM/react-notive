//
//  ContentView.swift
//  ReactNotive
//
//  Created by Emiel Mols on 30/05/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("SwiftUI lets you build UIs with simple, declarative code.")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Button(action: {
                print("Button tapped!")
            }) {
                Text("Tap me")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
