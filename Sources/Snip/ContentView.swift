import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: PlayerModel
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()

            if model.hasVideo {
                EditorView()
            } else {
                DropPrompt()
            }

            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.amber, lineWidth: 3)
                    .background(Color.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await model.load(url: url) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .navigationTitle(model.videoURL?.lastPathComponent ?? "Snip")
    }
}

struct DropPrompt: View {
    @EnvironmentObject var model: PlayerModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Color.amber)
            Text("Drop a video here")
                .font(.title2.weight(.semibold))
            Text("MP4, MOV, M4V — anything QuickTime can play")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Video…") { model.presentOpenPanel() }
                .controlSize(.large)
        }
        .padding(60)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.quaternary)
        )
    }
}

struct EditorView: View {
    @EnvironmentObject var model: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            videoStage
            if model.cropMode { cropBar }
            transport
            TimelineView()
                .padding(.horizontal, 18)
            bottomBar
        }
    }

    /// The video plus the crop overlay, which needs to know exactly where the
    /// aspect-fitted picture sits inside the black stage.
    private var videoStage: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                PlayerLayerView(player: model.player)
                    .frame(width: geo.size.width, height: geo.size.height)
                CropOverlay(videoRect: fittedVideoRect(in: geo.size))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func fittedVideoRect(in container: CGSize) -> CGRect {
        let size = model.naturalSize
        guard size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / size.width, container.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    private var cropBar: some View {
        HStack(spacing: 14) {
            Text("CROP")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.amber)

            Picker("", selection: $model.cropAspect) {
                ForEach(CropAspect.allCases) { aspect in
                    Text(aspect.rawValue).tag(aspect)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 380)
            .labelsHidden()

            Text("\(Int(model.outputSize.width))×\(Int(model.outputSize.height))")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button("Reset") { model.resetCrop() }
                .disabled(!model.isCropped)
            Button("Done") { model.cropMode = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.videoURL?.lastPathComponent ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(fileInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                model.presentOpenPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var fileInfo: String {
        let size = model.naturalSize
        var info = "\(Int(size.width))×\(Int(size.height)) · \(String(format: "%.3g", model.fps)) fps · \(timeString(model.duration))"
        if model.sourceFileBytes > 0 {
            info += " · \(ByteCountFormatter.string(fromByteCount: model.sourceFileBytes, countStyle: .file))"
        }
        return info
    }

    private var transport: some View {
        HStack(spacing: 16) {
            Group {
                Button { model.seek(to: model.trimStart) } label: {
                    Image(systemName: "arrow.left.to.line")
                }
                .help("Jump to selection start")

                Button { model.step(by: -1) } label: {
                    Image(systemName: "backward.frame.fill")
                }
                .help("Previous frame (←)")

                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .frame(width: 34)
                }
                .help("Play / pause (space)")

                Button { model.step(by: 1) } label: {
                    Image(systemName: "forward.frame.fill")
                }
                .help("Next frame (→)")

                Button { model.seek(to: model.trimEnd) } label: {
                    Image(systemName: "arrow.right.to.line")
                }
                .help("Jump to selection end")
            }
            .buttonStyle(.plain)
            .font(.system(size: 15))

            Text("\(timeString(model.currentTime))  ·  f\(frameIndex(model.currentTime, fps: model.fps))")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 170, alignment: .leading)

            Spacer()

            Button("Set In") { model.markIn() }
                .help("Set selection start to playhead (I)")
            Button("Set Out") { model.markOut() }
                .help("Set selection end to playhead (O)")
            Button { model.resetTrim() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset selection to full video")

            Divider().frame(height: 16)

            Button { model.toggleCropMode() } label: {
                Image(systemName: "crop")
                    .foregroundStyle(model.cropMode || model.isCropped ? Color.amber : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Crop the picture (C)")

            Button { model.loopSelection.toggle() } label: {
                Image(systemName: "repeat")
                    .foregroundStyle(model.loopSelection ? Color.amber : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Loop the selection (L)")

            Button { model.isMuted.toggle() } label: {
                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(model.isMuted ? Color.amber : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Mute (M)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 20) {
                timeBlock("IN", model.trimStart)
                timeBlock("LENGTH", model.selectionDuration)
                timeBlock("OUT", model.trimEnd)

                Spacer()

                if model.isCropped {
                    Text("Re-encode · required for crop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Cropping changes the picture, so the video has to be re-encoded.")
                } else {
                    Picker("", selection: $model.lossless) {
                        Text("Lossless").tag(true)
                        Text("Re-encode").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .help("Lossless is instant but cuts snap to keyframes. Re-encode is frame-exact.")
                }

                if model.willReencode {
                    Text(model.estimatedOutputBytes.map {
                        "≈ " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                    } ?? "estimating…")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 74, alignment: .leading)
                        .help("Estimated size of the re-encoded output")
                }

                if model.isExporting {
                    ProgressView(value: model.exportProgress)
                        .frame(width: 140)
                    Text("\(Int(model.exportProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Button("Export…") { model.beginExport() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.amber)
                        .foregroundStyle(.black)
                }
            }

            HStack {
                Text("space play · ←/→ frame · ⇧←/→ ±1s · I/O set in/out · hold a slider handle for frame-by-frame")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let status = model.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(Color.amber)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func timeBlock(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            Text("\(timeString(value)) · f\(frameIndex(value, fps: model.fps))")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
    }
}
