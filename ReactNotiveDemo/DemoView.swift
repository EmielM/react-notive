import SwiftUI

// This is just an example to quickly compare native SwiftUI with ReactNotive
struct DemoView: View {
    @State private var count = 0

    var body: some View {
        List {
            Text("Apple")
            Text("Banana")
            Text("Cherry")
        }
    }

//        VStack(spacing: 20) {
//            Text("Hello, World!")
//                .font(.largeTitle)
//                .fontWeight(.semibold)
//
//            Text("You tapped \(count) times")
//                .foregroundColor(.gray)
//
//            Button(action: {
//                count += 1
//            }) {
//                Text("Tap me")
//                    .padding()
//                    .frame(maxWidth: .infinity)
//                    .background(Color.blue)
//                    .foregroundColor(.white)
//                    .cornerRadius(10)
//            }
//        }
//        .padding()
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .background(.yellow)
//    }
}

struct DetailView: View {
    let item: Int

    var body: some View {
        VStack {
            Text("Detail for Item \(item)")
                .font(.largeTitle)
            NavigationLink("Go deeper", value: "Subpage for item \(item)")
        }
        .navigationDestination(for: String.self) { text in
            Text(text)
                .font(.title)
        }
    }
}
