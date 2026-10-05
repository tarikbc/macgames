import AppKit
import SwiftUI

/// Fills its frame with remote art, cropping around a focal point so the
/// subject stays in view at any window shape. Fades in once loaded.
struct ArtImage: View {
    let url: URL?
    var focus: UnitPoint = .center
    var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let url, let image = ArtworkStore.shared.image(url) {
                    FocalFill(image: image, size: geo.size, focus: focus, drift: drift)
                        .transition(.opacity)
                }
            }
            .animation(Motion.reveal, value: url.map { ArtworkStore.shared.images[$0] != nil } ?? false)
        }
        .clipped()
        // The cropped image extends past this frame. `clipped()` hides it but
        // does not stop it from taking clicks meant for views beside it.
        .allowsHitTesting(false)
    }
}

private struct FocalFill: View {
    let image: NSImage
    let size: CGSize
    let focus: UnitPoint
    let drift: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        let scale = max(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
        let w = image.size.width * scale, h = image.size.height * scale
        // Center the focal point, but never show past the image's edges.
        let x = min(0, max(size.width - w, size.width / 2 - focus.x * w))
        let y = min(0, max(size.height - h, size.height / 2 - focus.y * h))
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(drifting ? 1.07 : 1, anchor: focus)
            .onAppear {
                guard drift, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 38).repeatForever(autoreverses: true)) { drifting = true }
            }
    }
}

/// A logo or other image shown whole, never cropped.
struct ArtFit: View {
    let url: URL?
    /// Shown when there is no logo image, for games Steam does not sell.
    var fallback: String? = nil
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url, let image = ArtworkStore.shared.image(url) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else if url == nil, let fallback {
                Text(fallback)
                    .font(.system(size: 34, weight: .heavy).width(.condensed))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }
        }
        .animation(Motion.reveal, value: url.map { ArtworkStore.shared.images[$0] != nil } ?? false)
        .allowsHitTesting(false)
    }
}
