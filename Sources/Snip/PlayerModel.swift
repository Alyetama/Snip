import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PlayerModel: ObservableObject {
    static let shared = PlayerModel()

    let player = AVPlayer()

    @Published var videoURL: URL?
    @Published var duration: Double = 0
    @Published var fps: Double = 30
    @Published var naturalSize: CGSize = .zero
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var trimStart: Double = 0 { didSet { updateSizeEstimate() } }
    @Published var trimEnd: Double = 0 { didSet { updateSizeEstimate() } }
    @Published var loopSelection = false
    @Published var isMuted = false { didSet { player.isMuted = isMuted } }
    @Published var lossless = true { didSet { updateSizeEstimate() } }
    @Published var estimatedOutputBytes: Int64?
    @Published var sourceFileBytes: Int64 = 0
    @Published var thumbnails: [CGImage] = []
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var statusMessage: String? { didSet { if statusMessage != nil { scheduleStatusClear() } } }
    @Published var errorMessage: String?

    private var asset: AVURLAsset?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var statusClearTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var estimateTask: Task<Void, Never>?

    var hasVideo: Bool { videoURL != nil }
    var frameDuration: Double { fps > 0 ? 1.0 / fps : 1.0 / 30.0 }
    var selectionDuration: Double { max(0, trimEnd - trimStart) }

    private init() {
        installKeyMonitor()
    }

    // MARK: - Loading

    func load(url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let (durationTime, tracks, playable) = try await asset.load(.duration, .tracks, .isPlayable)
            guard playable else {
                errorMessage = "\(url.lastPathComponent) can't be played by AVFoundation. Convert to MP4/MOV first."
                return
            }
            guard let track = tracks.first(where: { $0.mediaType == .video }) else {
                errorMessage = "No video track found in \(url.lastPathComponent)."
                return
            }
            let (rate, size, transform) = try await track.load(.nominalFrameRate, .naturalSize, .preferredTransform)

            player.pause()
            isPlaying = false
            self.asset = asset
            videoURL = url
            duration = durationTime.seconds
            fps = rate > 0 ? Double(rate) : 30
            let transformed = size.applying(transform)
            naturalSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            sourceFileBytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            trimStart = 0
            trimEnd = duration
            currentTime = 0
            thumbnails = []

            let item = AVPlayerItem(asset: asset)
            player.replaceCurrentItem(with: item)
            installTimeObserver()
            installEndObserver(for: item)
            generateThumbnails()
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audiovisualContent]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await load(url: url) }
    }

    // MARK: - Playback

    func play() {
        guard hasVideo else { return }
        if loopSelection, currentTime < trimStart - 0.01 || currentTime >= trimEnd - frameDuration / 2 {
            seek(to: trimStart)
        } else if currentTime >= duration - frameDuration / 2 {
            seek(to: trimStart)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        guard hasVideo else { return }
        let t = max(0, min(seconds, duration))
        currentTime = t
        player.seek(
            to: CMTime(seconds: t, preferredTimescale: 240_000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func step(by frames: Int) {
        guard let item = player.currentItem else { return }
        pause()
        item.step(byCount: frames)
        currentTime = max(0, min(item.currentTime().seconds, duration))
    }

    func markIn() {
        trimStart = max(0, min(currentTime, trimEnd - frameDuration))
    }

    func markOut() {
        trimEnd = min(duration, max(currentTime, trimStart + frameDuration))
    }

    func resetTrim() {
        trimStart = 0
        trimEnd = duration
    }

    private func installTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        let interval = CMTime(value: 1, timescale: 60)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                if self.isPlaying, self.loopSelection, time.seconds >= self.trimEnd {
                    self.seek(to: self.trimStart)
                    self.player.play()
                }
            }
        }
    }

    private func installEndObserver(for item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.loopSelection {
                    self.seek(to: self.trimStart)
                    self.player.play()
                } else {
                    self.isPlaying = false
                }
            }
        }
    }

    // MARK: - Thumbnails

    private func generateThumbnails(count: Int = 28) {
        guard let asset, duration > 0 else { return }
        thumbnailTask?.cancel()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 120)
        let tolerance = CMTime(seconds: max(duration / Double(count) / 2, 0.05), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let total = duration
        let times = (0..<count).map {
            CMTime(seconds: total * (Double($0) + 0.5) / Double(count), preferredTimescale: 600)
        }
        thumbnailTask = Task { [weak self] in
            for await result in generator.images(for: times) {
                if Task.isCancelled { return }
                if let image = try? result.image {
                    self?.thumbnails.append(image)
                }
            }
        }
    }

    // MARK: - Export

    /// Estimated re-encoded output size, debounced so handle drags don't spam sessions.
    private func updateSizeEstimate() {
        estimateTask?.cancel()
        estimatedOutputBytes = nil
        guard !lossless, let asset, let src = videoURL, selectionDuration > 0 else { return }
        let start = trimStart
        let end = trimEnd
        let fileType: AVFileType = ["mp4", "m4v"].contains(src.pathExtension.lowercased()) ? .mp4 : .mov
        estimateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return }
            let ts: CMTimeScale = 240_000
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: ts),
                end: CMTime(seconds: end, preferredTimescale: ts)
            )
            session.outputFileType = fileType
            let bytes: Int64 = await withCheckedContinuation { continuation in
                session.estimateOutputFileLength { length, _ in
                    continuation.resume(returning: length)
                }
            }
            guard !Task.isCancelled else { return }
            self?.estimatedOutputBytes = bytes > 0 ? bytes : nil
        }
    }

    func beginExport() {
        guard let src = videoURL, !isExporting else { return }
        let ext = ["mp4", "m4v"].contains(src.pathExtension.lowercased()) ? "mp4" : "mov"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .movie]
        panel.nameFieldStringValue = src.deletingPathExtension().lastPathComponent + "-trimmed." + ext
        panel.directoryURL = src.deletingLastPathComponent()
        guard panel.runModal() == .OK, let out = panel.url else { return }
        Task { await runExport(to: out) }
    }

    private func runExport(to out: URL) async {
        guard let asset, let src = videoURL else { return }
        guard out.standardizedFileURL != src.standardizedFileURL else {
            errorMessage = "That would overwrite the original video. Pick a different name."
            return
        }
        pause()
        let preset = lossless ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            errorMessage = "Could not create an export session."
            return
        }
        let ts: CMTimeScale = 240_000
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: ts),
            end: CMTime(seconds: trimEnd, preferredTimescale: ts)
        )
        let fileType: AVFileType = out.pathExtension.lowercased() == "mp4" ? .mp4 : .mov

        isExporting = true
        exportProgress = 0
        let monitor = Task { [weak self] in
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let progress) = state {
                    await MainActor.run { self?.exportProgress = progress.fractionCompleted }
                }
            }
        }
        // Export to a hidden temp sibling, then swap in — a failed export can
        // never destroy whatever file the user chose to overwrite.
        let temp = out.deletingLastPathComponent()
            .appendingPathComponent(".snip-\(UUID().uuidString).\(out.pathExtension)")
        do {
            try await session.export(to: temp, as: fileType)
            if FileManager.default.fileExists(atPath: out.path) {
                _ = try FileManager.default.replaceItemAt(out, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: out)
            }
            statusMessage = "Exported \(out.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            try? FileManager.default.removeItem(at: temp)
            var message = "Export failed: \(error.localizedDescription)"
            if lossless { message += " — try the Re-encode mode." }
            errorMessage = message
        }
        monitor.cancel()
        isExporting = false
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                PlayerModel.shared.handleKey(event) ? nil : event
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard hasVideo, !isExporting else { return false }
        // Don't swallow menu shortcuts or typing in panels (open/save dialogs).
        if event.modifierFlags.contains(.command) { return false }
        if NSApp.modalWindow != nil { return false }
        if let window = NSApp.keyWindow, window is NSPanel || window.isSheet || window.attachedSheet != nil {
            return false
        }

        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 49: // space
            togglePlay()
            return true
        case 123: // left arrow
            shift ? seek(to: currentTime - 1) : step(by: -1)
            return true
        case 124: // right arrow
            shift ? seek(to: currentTime + 1) : step(by: 1)
            return true
        default:
            break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "i": markIn(); return true
        case "o": markOut(); return true
        case "l": loopSelection.toggle(); return true
        case "m": isMuted.toggle(); return true
        default: return false
        }
    }

    private func scheduleStatusClear() {
        statusClearTask?.cancel()
        statusClearTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { self.statusMessage = nil }
        }
    }
}
