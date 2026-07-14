import SwiftUI

/// Drag state for a scrub target (trim handle or playhead) that supports
/// hold-to-enter frame-by-frame mode: keep the mouse still for 0.45 s while
/// pressed and further movement maps 8 px = 1 frame.
struct FineDrag {
    var active = false
    var frameMode = false
    var anchorTime: Double = 0
    var anchorX: CGFloat = 0
    var lastX: CGFloat = 0
    var pending: DispatchWorkItem?
}

struct TimelineView: View {
    @EnvironmentObject var model: PlayerModel
    @State private var startDrag = FineDrag()
    @State private var endDrag = FineDrag()
    @State private var headDrag = FineDrag()

    private let handleW: CGFloat = 16
    private let stripH: CGFloat = 56
    private let stripTop: CGFloat = 30
    private let pixelsPerFrame: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let xStart = xFor(model.trimStart, width: width)
            let xEnd = xFor(model.trimEnd, width: width)
            let xHead = xFor(model.currentTime, width: width)
            let usable = max(width - 2 * handleW, 1)

            ZStack(alignment: .topLeading) {
                // Thumbnail strip — dragging it scrubs the playhead.
                thumbnailStrip
                    .frame(width: usable, height: stripH)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .offset(x: handleW, y: stripTop)
                    .gesture(
                        fineDrag($headDrag, width: width, onStart: {},
                                 get: { model.currentTime },
                                 set: { model.seek(to: $0) })
                    )

                // Dimmed areas outside the selection.
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .frame(width: max(0, xStart - handleW), height: stripH)
                    .offset(x: handleW, y: stripTop)
                    .allowsHitTesting(false)
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .frame(width: max(0, width - handleW - xEnd), height: stripH)
                    .offset(x: xEnd, y: stripTop)
                    .allowsHitTesting(false)

                // Selection rails (top and bottom).
                Rectangle()
                    .fill(Color.amber)
                    .frame(width: max(0, xEnd - xStart), height: 3)
                    .offset(x: xStart, y: stripTop - 3)
                    .allowsHitTesting(false)
                Rectangle()
                    .fill(Color.amber)
                    .frame(width: max(0, xEnd - xStart), height: 3)
                    .offset(x: xStart, y: stripTop + stripH)
                    .allowsHitTesting(false)

                // Trim handles.
                handle(icon: "chevron.compact.left", frameMode: startDrag.frameMode, biasLeft: true)
                    .offset(x: xStart - handleW, y: stripTop - 3)
                    .gesture(
                        fineDrag($startDrag, width: width, onStart: { model.pause() },
                                 get: { model.trimStart },
                                 set: { newValue in
                                     let clamped = max(0, min(newValue, model.trimEnd - model.frameDuration))
                                     model.trimStart = clamped
                                     model.seek(to: clamped)
                                 })
                    )
                handle(icon: "chevron.compact.right", frameMode: endDrag.frameMode, biasLeft: false)
                    .offset(x: xEnd, y: stripTop - 3)
                    .gesture(
                        fineDrag($endDrag, width: width, onStart: { model.pause() },
                                 get: { model.trimEnd },
                                 set: { newValue in
                                     let clamped = min(model.duration, max(newValue, model.trimStart + model.frameDuration))
                                     model.trimEnd = clamped
                                     model.seek(to: clamped)
                                 })
                    )

                // Playhead.
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .offset(x: xHead - 4.5, y: stripTop - 12)
                    .allowsHitTesting(false)
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: stripH + 12)
                    .offset(x: xHead - 1, y: stripTop - 6)
                    .allowsHitTesting(false)
                    .shadow(color: .black.opacity(0.6), radius: 1)

                // Scrub bubble.
                if let info = bubbleInfo(width: width) {
                    HStack(spacing: 6) {
                        Text(info.label)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        if info.frameMode {
                            Text("FRAME")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.amber, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(info.frameMode ? Color.amber : Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .fixedSize()
                    .position(x: min(max(info.x, 90), width - 90), y: 11)
                    .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "timeline")
        }
        .frame(height: 92)
    }

    // MARK: - Pieces

    private var thumbnailStrip: some View {
        HStack(spacing: 0) {
            if model.thumbnails.isEmpty {
                Rectangle().fill(Color.white.opacity(0.06))
            } else {
                ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: stripH)
                        .clipped()
                }
            }
        }
        .background(Color.white.opacity(0.06))
    }

    private func handle(icon: String, frameMode: Bool, biasLeft: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(frameMode ? Color.white : Color.amber)
            .frame(width: handleW, height: stripH + 6)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
            )
            // Hit area grows outward from the selection so both handles stay
            // grabbable when the selection is near zero-width.
            .contentShape(Path(CGRect(
                x: biasLeft ? -14 : -2,
                y: -10,
                width: handleW + 16,
                height: stripH + 26
            )))
    }

    private func bubbleInfo(width: CGFloat) -> (label: String, x: CGFloat, frameMode: Bool)? {
        if startDrag.active {
            return ("IN  \(timeString(model.trimStart)) · f\(frameIndex(model.trimStart, fps: model.fps))",
                    xFor(model.trimStart, width: width), startDrag.frameMode)
        }
        if endDrag.active {
            return ("OUT  \(timeString(model.trimEnd)) · f\(frameIndex(model.trimEnd, fps: model.fps))",
                    xFor(model.trimEnd, width: width), endDrag.frameMode)
        }
        if headDrag.active {
            return ("\(timeString(model.currentTime)) · f\(frameIndex(model.currentTime, fps: model.fps))",
                    xFor(model.currentTime, width: width), headDrag.frameMode)
        }
        return nil
    }

    // MARK: - Mapping

    private func xFor(_ time: Double, width: CGFloat) -> CGFloat {
        let dur = max(model.duration, 0.0001)
        let usable = max(width - 2 * handleW, 1)
        return handleW + CGFloat(time / dur) * usable
    }

    private func timeFor(x: CGFloat, width: CGFloat) -> Double {
        let dur = max(model.duration, 0.0001)
        let usable = max(width - 2 * handleW, 1)
        let fraction = Double((x - handleW) / usable)
        return max(0, min(fraction, 1)) * dur
    }

    // MARK: - Fine drag gesture

    private func fineDrag(
        _ drag: Binding<FineDrag>,
        width: CGFloat,
        onStart: @escaping () -> Void,
        get: @escaping () -> Double,
        set: @escaping (Double) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
            .onChanged { gesture in
                let x = gesture.location.x
                var state = drag.wrappedValue
                if !state.active {
                    state.active = true
                    state.frameMode = false
                    state.anchorTime = get()
                    state.anchorX = x
                    state.lastX = x
                    onStart()
                    state.pending?.cancel()
                    state.pending = scheduleHold(drag, get: get)
                }
                if state.frameMode {
                    let frames = ((x - state.anchorX) / pixelsPerFrame).rounded()
                    set(state.anchorTime + Double(frames) * model.frameDuration)
                } else {
                    if abs(x - state.lastX) > 1.5 {
                        state.lastX = x
                        state.pending?.cancel()
                        state.pending = scheduleHold(drag, get: get)
                    }
                    set(timeFor(x: x, width: width))
                }
                drag.wrappedValue = state
            }
            .onEnded { _ in
                drag.wrappedValue.pending?.cancel()
                drag.wrappedValue = FineDrag()
            }
    }

    private func scheduleHold(_ drag: Binding<FineDrag>, get: @escaping () -> Double) -> DispatchWorkItem {
        let item = DispatchWorkItem {
            var state = drag.wrappedValue
            guard state.active, !state.frameMode else { return }
            state.frameMode = true
            state.anchorTime = get()
            state.anchorX = state.lastX
            drag.wrappedValue = state
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
        return item
    }
}
