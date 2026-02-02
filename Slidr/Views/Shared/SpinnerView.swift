import SwiftUI

/// A pure SwiftUI spinning indicator that avoids the AppKitProgressView layout warnings.
/// Use in place of `ProgressView().controlSize(.small)` for inline spinners.
struct SpinnerView: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "progress.indicator")
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}
