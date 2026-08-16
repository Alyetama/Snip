import SwiftUI

/// Which part of the crop rectangle a drag is moving.
enum CropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var isCorner: Bool { movesLeft || movesRight ? (movesTop || movesBottom) : false }

    /// Position of the handle within a rect, as unit coordinates.
    var unitPoint: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: 0.5, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .right: return CGPoint(x: 1, y: 0.5)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        case .bottom: return CGPoint(x: 0.5, y: 1)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        case .left: return CGPoint(x: 0, y: 0.5)
        }
    }
}

/// Interactive crop rectangle drawn over the video. All crop math happens in
/// video pixel space (origin top-left); this view only scales it to the
/// on-screen video rect.
struct CropOverlay: View {
    @EnvironmentObject var model: PlayerModel
    /// Where the video is actually drawn inside this view (aspect-fit).
    let videoRect: CGRect

    @State private var dragStartCrop: CGRect?

    private let handleHit: CGFloat = 24
    private let minSidePixels: CGFloat = 16

    private var scale: CGFloat {
        model.naturalSize.width > 0 ? videoRect.width / model.naturalSize.width : 1
    }

    /// The crop rect converted from video pixels to this view's coordinates.
    private var screenCrop: CGRect {
        CGRect(
            x: videoRect.minX + model.cropRect.minX * scale,
            y: videoRect.minY + model.cropRect.minY * scale,
            width: model.cropRect.width * scale,
            height: model.cropRect.height * scale
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.cropMode {
                // Dim everything outside the crop.
                Path { path in
                    path.addRect(videoRect)
                    path.addRect(screenCrop)
                }
                .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                thirdsGuides
                border
                interiorDragTarget
                ForEach(Array(CropHandle.allCases.enumerated()), id: \.offset) { _, handle in
                    handleView(handle)
                }
            } else if model.isCropped {
                // Not editing, but a crop is set — show what will be exported.
                Rectangle()
                    .strokeBorder(Color.amber.opacity(0.9), lineWidth: 1.5)
                    .frame(width: screenCrop.width, height: screenCrop.height)
                    .offset(x: screenCrop.minX, y: screenCrop.minY)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Pieces

    private var border: some View {
        Rectangle()
            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
            .frame(width: screenCrop.width, height: screenCrop.height)
            .offset(x: screenCrop.minX, y: screenCrop.minY)
            .allowsHitTesting(false)
    }

    private var thirdsGuides: some View {
        Path { path in
            for i in 1...2 {
                let x = screenCrop.minX + screenCrop.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: screenCrop.minY))
                path.addLine(to: CGPoint(x: x, y: screenCrop.maxY))
                let y = screenCrop.minY + screenCrop.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: screenCrop.minX, y: y))
                path.addLine(to: CGPoint(x: screenCrop.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.28), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    /// Dragging inside the rect moves the whole crop.
    private var interiorDragTarget: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: max(screenCrop.width, 1), height: max(screenCrop.height, 1))
            .offset(x: screenCrop.minX, y: screenCrop.minY)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let start = dragStartCrop ?? model.cropRect
                        if dragStartCrop == nil { dragStartCrop = start; model.pause() }
                        var moved = start
                        moved.origin.x += gesture.translation.width / scale
                        moved.origin.y += gesture.translation.height / scale
                        model.cropRect = clampInsideFrame(moved)
                    }
                    .onEnded { _ in dragStartCrop = nil }
            )
    }

    private func handleView(_ handle: CropHandle) -> some View {
        let point = handle.unitPoint
        let x = screenCrop.minX + screenCrop.width * point.x
        let y = screenCrop.minY + screenCrop.height * point.y
        let isCorner = handle.isCorner
        return ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white)
                .frame(
                    width: isCorner ? 12 : (handle == .top || handle == .bottom ? 26 : 4),
                    height: isCorner ? 12 : (handle == .top || handle == .bottom ? 4 : 26)
                )
                .shadow(color: .black.opacity(0.5), radius: 1.5)
        }
        .frame(width: handleHit, height: handleHit)
        .contentShape(Rectangle())
        .position(x: x, y: y)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let start = dragStartCrop ?? model.cropRect
                    if dragStartCrop == nil { dragStartCrop = start; model.pause() }
                    model.cropRect = resized(
                        start,
                        handle: handle,
                        delta: CGSize(
                            width: gesture.translation.width / scale,
                            height: gesture.translation.height / scale
                        )
                    )
                }
                .onEnded { _ in dragStartCrop = nil }
        )
    }

    // MARK: - Geometry

    private var frameSize: CGSize { model.naturalSize }

    private func clampInsideFrame(_ rect: CGRect) -> CGRect {
        var result = rect
        result.size.width = min(result.width, frameSize.width)
        result.size.height = min(result.height, frameSize.height)
        result.origin.x = min(max(0, result.origin.x), frameSize.width - result.width)
        result.origin.y = min(max(0, result.origin.y), frameSize.height - result.height)
        return result
    }

    private func resized(_ start: CGRect, handle: CropHandle, delta: CGSize) -> CGRect {
        var left = start.minX
        var right = start.maxX
        var top = start.minY
        var bottom = start.maxY

        if handle.movesLeft { left = min(start.minX + delta.width, right - minSidePixels) }
        if handle.movesRight { right = max(start.maxX + delta.width, left + minSidePixels) }
        if handle.movesTop { top = min(start.minY + delta.height, bottom - minSidePixels) }
        if handle.movesBottom { bottom = max(start.maxY + delta.height, top + minSidePixels) }

        left = max(0, left)
        top = max(0, top)
        right = min(frameSize.width, right)
        bottom = min(frameSize.height, bottom)

        var rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)

        if let ratio = model.cropAspect.ratio(original: frameSize) {
            rect = conform(rect, to: ratio, handle: handle, anchor: start)
        }
        return clampInsideFrame(rect)
    }

    /// Force `rect` to the given width:height ratio, keeping the edge the user
    /// isn't dragging pinned in place.
    private func conform(_ rect: CGRect, to ratio: CGFloat, handle: CropHandle, anchor: CGRect) -> CGRect {
        var result = rect
        let widthDriven = handle.isCorner || handle == .left || handle == .right

        if widthDriven {
            result.size.width = min(rect.width, frameSize.width)
            result.size.height = result.width / ratio
            if result.height > frameSize.height {
                result.size.height = frameSize.height
                result.size.width = result.height * ratio
            }
        } else {
            result.size.height = min(rect.height, frameSize.height)
            result.size.width = result.height * ratio
            if result.width > frameSize.width {
                result.size.width = frameSize.width
                result.size.height = result.width / ratio
            }
        }

        // Pin the side opposite the handle so the rect grows the way the drag felt.
        result.origin.x = handle.movesLeft ? rect.maxX - result.width : rect.minX
        result.origin.y = handle.movesTop ? rect.maxY - result.height : rect.minY

        // Edge handles keep the perpendicular axis centered on where it was.
        if handle == .left || handle == .right {
            result.origin.y = anchor.midY - result.height / 2
        } else if handle == .top || handle == .bottom {
            result.origin.x = anchor.midX - result.width / 2
        }
        return result
    }
}
