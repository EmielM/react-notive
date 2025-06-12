import SwiftUI

// This is just an example to quickly compare native SwiftUI with ReactNotive
struct NativeView: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Hello, World!")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("You tapped \(count) times")
                .foregroundColor(.gray)

            Button(action: {
                count += 1
            }) {
                Text("Tap me")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.yellow)
    }
}
