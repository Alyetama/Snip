import AVFoundation
import AppKit
import SwiftUI

extension Color {
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.23)
}

/// AVPlayerLayer host — lighter than VideoPlayer and shows no built-in controls.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        PlayerNSView(player: player)
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {}
}

final class PlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Time formatting

func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00.000" }
    let total = max(0, seconds)
    let hours = Int(total) / 3600
    let minutes = (Int(total) % 3600) / 60
    let secs = Int(total) % 60
    let millis = Int(((total - floor(total)) * 1000).rounded())
    if hours > 0 {
        return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }
    return String(format: "%d:%02d.%03d", minutes, secs, millis)
}

func frameIndex(_ seconds: Double, fps: Double) -> Int {
    max(0, Int((seconds * max(fps, 1)).rounded()))
}
