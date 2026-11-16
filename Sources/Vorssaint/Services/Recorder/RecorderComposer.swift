// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import CoreImage

/// Turns a recording plus an edit into the picture the person sees, for both
/// the editor preview and the export. One function decides what a frame looks
/// like, so what is watched while editing and what lands in the file are the
/// same pixels by construction.
///
/// Everything that does not change frame to frame is rendered once into a
/// plate: the background, the shadow under the recording, the rounded mask.
/// Per frame there is a transform, a mask and a composite, which is what keeps
/// a Retina export running faster than the encoder behind it.
final class RecorderComposer {

    // MARK: - Plan

    /// Everything precomputed for one document and one pointer track. The
    /// per-frame arrays are the offline advantage made concrete: smoothing and
    /// zoom both need to see the whole recording, so they are solved once,
    /// here, and every frame is then an index lookup.
    struct Plan {
        let sourceSize: CGSize
        let canvasSize: CGSize
        let cardRect: CGRect
        let frameRate: Int
        let positions: [CGPoint]
        let zoom: [Double]
        let travel: [CGPoint]
        let pressScale: [Double]
        let ring: [Double]
        let showsPointer: Bool
        /// The real pointer images the recording showed, in the order the
        /// track packed them.
        let pointerShapes: [RecorderPointerTrack.CursorShape]
        /// Which of those is on screen at each frame.
        let pointerShapeIndex: [Int]
        /// Whether a pointer was on screen at all at each frame.
        let pointerVisible: [Bool]
        /// How solid the drawn pointer is, so one parked in a corner fades
        /// out of the way and is back before it moves again.
        let pointerOpacity: [Double]
        /// Points to pixels for the pointer: the display's own scale, times
        /// the accessibility pointer size, times what the person chose.
        let pointerScale: CGFloat
        /// What a pointer of a typical size comes out as, used to size the
        /// click ring so it stays in proportion.
        let pointerPixelSize: CGFloat
        let showsClickRing: Bool
        let plate: CIImage?
        let mask: CIImage?
        /// Lines of text and, for each frame, how solid each one is. Solved
        /// once like everything else, so a frame is a lookup.
        let texts: [RecorderTextOverlay]
        let textOpacity: [[Double]]
        /// Pictures laid over the recording, each already resized to the
        /// pixels it is drawn at, with the same per-frame solidity.
        let images: [RecorderImageOverlay]
        let imageSprites: [CGImage?]
        let imageOpacity: [[Double]]
        /// Areas kept unreadable and, for each frame, whether each one is on.
        let blurs: [RecorderBlurRegion]
        let blurCovers: [[Bool]]
        let motionBlurEnabled: Bool
        let motionBlurStrength: Double
        let cameraBubble: RecorderCameraBubbleConfig
        let keystrokesEnabled: Bool
        let keystrokes: [RecorderKeystrokeEvent]
        let captionsEnabled: Bool
        let captions: [RecorderCaptionSegment]
        let sourceTimes: [Double]
        let cameraURL: URL?
        let cameraBubbleScale: [Double]
        let perspectiveTiltEnabled: Bool
        let tiltX: [Double]
        let tiltY: [Double]
        let ambientGlowEnabled: Bool
        let preservesTransparentBackdrop: Bool
    }

    private let plan: Plan
    /// Decoded once. A recording normally shows two or three pointer shapes,
    /// so this is a handful of small images for the whole export.
    private let decodedShapes: [CGImage?]
    private let fallbackArrow: CGImage?
    private let cameraSampler: CameraFrameSampler?

    init(plan: Plan) {
        self.plan = plan
        decodedShapes = plan.showsPointer ? plan.pointerShapes.map { $0.image } : []
        // Only reached when the recording never managed to read a real
        // pointer image, which is the one case where a drawn arrow beats no
        // pointer at all.
        fallbackArrow = (plan.showsPointer && plan.pointerShapes.isEmpty)
            ? RecorderCursorSprite.arrow(pixelSize: plan.pointerPixelSize * 3)
            : nil
        cameraSampler = (plan.cameraBubble.isEnabled && plan.cameraURL != nil)
            ? plan.cameraURL.flatMap(CameraFrameSampler.init(url:))
            : nil
    }

    var canvasSize: CGSize { plan.canvasSize }

    func prepareAssets() async {
        await cameraSampler?.prepare()
    }

    // MARK: - Rendering

    func render(_ source: CIImage, at seconds: Double) -> CIImage {
        let index = frameIndex(for: seconds)
        var content = source.cropped(to: CGRect(origin: .zero, size: plan.sourceSize))
        content = blurred(content, at: seconds)

        let pointerWasOnScreen = plan.pointerVisible.indices.contains(index)
            ? plan.pointerVisible[index] : true
        let opacity = plan.pointerOpacity.indices.contains(index) ? plan.pointerOpacity[index] : 1
        if plan.showsPointer, pointerWasOnScreen, opacity > 0.01, index < plan.positions.count {
            content = drawPointer(on: content, index: index)
        }
        content = zoomed(content, index: index)
        if plan.motionBlurEnabled, index > 0,
           plan.positions.indices.contains(index),
           plan.positions.indices.contains(index - 1) {
            let prev = plan.positions[index - 1]
            let curr = plan.positions[index]
            let zoomFactor = plan.zoom.indices.contains(index) ? plan.zoom[index] : 1.0
            let strength = max(0, min(1, plan.motionBlurStrength)) * 2.5
            let velocity = CGVector(
                dx: (curr.x - prev.x) * zoomFactor * strength,
                dy: (curr.y - prev.y) * zoomFactor * strength
            )
            if hypot(velocity.dx, velocity.dy) > 0.5 {
                content = VorssaintMetalShaders.shared.applyDirectionalMotionBlur(
                    to: content,
                    velocity: velocity,
                    samples: 9
                )
            }
        }
        let fittedContent = fitted(content)
        let canvasBounds = CGRect(origin: .zero, size: plan.canvasSize)

        var stageCard = fittedContent
        if let mask = plan.mask {
            stageCard = stageCard.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask,
            ])
        }
        if plan.perspectiveTiltEnabled {
            stageCard = perspectiveTilted(stageCard, index: index)
        }

        var background: CIImage
        if let plate = plan.plate {
            background = plate
        } else if plan.preservesTransparentBackdrop {
            background = CIImage.empty()
        } else {
            background = CIImage(color: .black).cropped(to: canvasBounds)
        }

        if plan.ambientGlowEnabled {
            background = ambientGlow(from: fittedContent, over: background)
        }

        if plan.mask != nil || plan.plate != nil || plan.ambientGlowEnabled
            || plan.perspectiveTiltEnabled || plan.preservesTransparentBackdrop {
            content = stageCard.composited(over: background)
        } else {
            content = fittedContent
        }

        let sourceSeconds = plan.sourceTimes.indices.contains(index) ? plan.sourceTimes[index] : seconds
        content = drawImages(on: content, index: index)
        content = drawTexts(on: content, index: index)
        content = drawCameraBubble(on: content, index: index, sourceSeconds: sourceSeconds)
        content = drawKeystrokeHUD(on: content, at: sourceSeconds)
        content = drawCaptions(on: content, at: sourceSeconds)
        return content.cropped(to: canvasBounds)
    }

    private func perspectiveTilted(_ image: CIImage, index: Int) -> CIImage {
        let tx = plan.tiltX.indices.contains(index) ? plan.tiltX[index] : 0
        let ty = plan.tiltY.indices.contains(index) ? plan.tiltY[index] : 0
        guard abs(tx) > 0.002 || abs(ty) > 0.002 else { return image }

        let rect = plan.cardRect
        guard rect.width > 4, rect.height > 4,
              let filter = CIFilter(name: "CIPerspectiveTransform") else { return image }

        let maxInsetX = rect.width * 0.028
        let maxInsetY = rect.height * 0.032
        let leftInsetY = CGFloat(max(0, -tx)) * maxInsetY
        let rightInsetY = CGFloat(max(0, tx)) * maxInsetY
        let topInsetX = CGFloat(max(0, -ty)) * maxInsetX
        let bottomInsetX = CGFloat(max(0, ty)) * maxInsetX

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: rect.minX + topInsetX, y: rect.maxY - leftInsetY), forKey: "inputTopLeft")
        filter.setValue(CIVector(x: rect.maxX - topInsetX, y: rect.maxY - rightInsetY), forKey: "inputTopRight")
        filter.setValue(CIVector(x: rect.maxX - bottomInsetX, y: rect.minY + rightInsetY), forKey: "inputBottomRight")
        filter.setValue(CIVector(x: rect.minX + bottomInsetX, y: rect.minY + leftInsetY), forKey: "inputBottomLeft")
        return filter.outputImage ?? image
    }

    private func ambientGlow(from fittedContent: CIImage, over background: CIImage) -> CIImage {
        let canvasBounds = CGRect(origin: .zero, size: plan.canvasSize)
        let center = CGPoint(x: plan.cardRect.midX, y: plan.cardRect.midY)
        let glowScale: CGFloat = 1.09
        let blurRadius = max(18, min(plan.canvasSize.width, plan.canvasSize.height) * 0.055)
        let toCenter = CGAffineTransform(translationX: -center.x, y: -center.y)
        let scaled = CGAffineTransform(scaleX: glowScale, y: glowScale)
        let back = CGAffineTransform(translationX: center.x, y: center.y)
        let halo = fittedContent
            .transformed(by: toCenter.concatenating(scaled).concatenating(back))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: canvasBounds)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.58),
            ])
        return halo.composited(over: background)
    }

    /// Pictures share the captions' place above the zoom, and go under them:
    /// a mark of your own belongs behind what the recording is saying.
    private func drawImages(on content: CIImage, index: Int) -> CIImage {
        guard !plan.images.isEmpty else { return content }
        var result = content
        for (order, overlay) in plan.images.enumerated() {
            guard plan.imageOpacity.indices.contains(order),
                  plan.imageOpacity[order].indices.contains(index),
                  plan.imageSprites.indices.contains(order),
                  let sprite = plan.imageSprites[order] else { continue }
            let opacity = plan.imageOpacity[order][index]
            guard opacity > 0.01 else { continue }
            let size = CGSize(width: sprite.width, height: sprite.height)
            let origin = overlay.anchor.origin(of: size, in: plan.canvasSize)
            result = faded(CIImage(cgImage: sprite), opacity: opacity)
                .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .composited(over: result)
        }
        return result
    }

    /// Text sits on top of everything, including the background and the zoom:
    /// a caption that got magnified along with the picture would leave the
    /// frame the moment the zoom moved.
    private func drawTexts(on content: CIImage, index: Int) -> CIImage {
        guard !plan.texts.isEmpty else { return content }
        var result = content
        for (order, overlay) in plan.texts.enumerated() {
            guard plan.textOpacity.indices.contains(order),
                  plan.textOpacity[order].indices.contains(index) else { continue }
            let opacity = plan.textOpacity[order][index]
            guard opacity > 0.01,
                  let image = RecorderTextRenderer.image(for: overlay,
                                                         canvasHeight: plan.canvasSize.height)
            else { continue }
            let size = CGSize(width: image.width, height: image.height)
            let origin = overlay.anchor.origin(of: size, in: plan.canvasSize)
            result = faded(CIImage(cgImage: image), opacity: opacity)
                .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .composited(over: result)
        }
        return result
    }

    private func drawCameraBubble(on content: CIImage, index: Int, sourceSeconds: Double) -> CIImage {
        let cfg = plan.cameraBubble
        guard cfg.isEnabled else { return content }
        let scale: CGFloat
        if plan.cameraBubbleScale.indices.contains(index) {
            scale = CGFloat(plan.cameraBubbleScale[index])
        } else {
            let pointerNorm: CGPoint? = plan.positions.indices.contains(index) ? plan.positions[index] : nil
            scale = cfg.effectiveScale(pointerNormalized: pointerNorm)
        }
        let minor = min(plan.canvasSize.width, plan.canvasSize.height)
        let diameter = max(44, minor * CGFloat(cfg.diameterFraction) * scale)
        let center = CGPoint(
            x: cfg.normalizedCenter.x * plan.canvasSize.width,
            y: (1.0 - cfg.normalizedCenter.y) * plan.canvasSize.height
        )
        let pad: CGFloat = 14
        let size = CGSize(width: ceil(diameter + pad * 2), height: ceil(diameter + pad * 2))
        guard let ctx = CGContext(data: nil,
                                  width: Int(size.width),
                                  height: Int(size.height),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return content }
        let circleRect = CGRect(x: pad, y: pad, width: diameter, height: diameter)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4),
                      blur: 10,
                      color: CGColor(gray: 0, alpha: 0.45))
        ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1))
        ctx.fillEllipse(in: circleRect)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addEllipse(in: circleRect)
        ctx.clip()
        if let cameraFrame = cameraSampler?.frame(at: sourceSeconds),
           cameraFrame.width > 0, cameraFrame.height > 0 {
            let srcW = CGFloat(cameraFrame.width)
            let srcH = CGFloat(cameraFrame.height)
            let fill = max(circleRect.width / srcW, circleRect.height / srcH)
            let drawW = srcW * fill
            let drawH = srcH * fill
            let drawRect = CGRect(
                x: circleRect.midX - drawW / 2,
                y: circleRect.midY - drawH / 2,
                width: drawW,
                height: drawH
            )
            ctx.interpolationQuality = .high
            ctx.draw(cameraFrame, in: drawRect)
        } else {
            ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 0.94))
            ctx.fill(circleRect)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.34))
            let headSize = diameter * 0.28
            let headRect = CGRect(
                x: circleRect.midX - headSize / 2,
                y: circleRect.midY + diameter * 0.04,
                width: headSize,
                height: headSize
            )
            ctx.fillEllipse(in: headRect)
            let shouldersW = diameter * 0.56
            let shouldersH = diameter * 0.36
            let shouldersRect = CGRect(
                x: circleRect.midX - shouldersW / 2,
                y: circleRect.minY - shouldersH * 0.22,
                width: shouldersW,
                height: shouldersH
            )
            ctx.fillEllipse(in: shouldersRect)
        }
        ctx.restoreGState()

        ctx.setStrokeColor(Self.borderCGColor(hex: cfg.borderHex))
        ctx.setLineWidth(max(2.0, diameter * 0.025))
        ctx.strokeEllipse(in: circleRect)

        guard let cg = ctx.makeImage() else { return content }
        let ox = center.x - size.width / 2
        let oy = center.y - size.height / 2
        return CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(translationX: ox, y: oy))
            .composited(over: content)
    }

    private static func borderCGColor(hex: String) -> CGColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.88)
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 0.88)
    }

    private func drawKeystrokeHUD(on content: CIImage, at seconds: Double) -> CIImage {
        guard plan.keystrokesEnabled, !plan.keystrokes.isEmpty else { return content }
        let active = RecorderKeystrokeEvent.activeEvents(in: plan.keystrokes, at: seconds)
        guard !active.isEmpty else { return content }
        let text = active.map(\.formattedCapString).joined(separator: "  ")
        guard let pill = renderStudioPill(text: text, fontSize: max(18, plan.canvasSize.height * 0.026)) else {
            return content
        }
        let ox = (plan.canvasSize.width - CGFloat(pill.width)) / 2
        let oy = plan.captionsEnabled && RecorderCaptionSegment.activeCaption(in: plan.captions, at: seconds) != nil
            ? plan.canvasSize.height * 0.13
            : plan.canvasSize.height * 0.06
        return CIImage(cgImage: pill)
            .transformed(by: CGAffineTransform(translationX: ox, y: oy))
            .composited(over: content)
    }

    private func drawCaptions(on content: CIImage, at seconds: Double) -> CIImage {
        guard plan.captionsEnabled,
              let segment = RecorderCaptionSegment.activeCaption(in: plan.captions, at: seconds),
              let pill = renderStudioPill(text: segment.text, fontSize: max(18, plan.canvasSize.height * 0.028))
        else { return content }
        let ox = (plan.canvasSize.width - CGFloat(pill.width)) / 2
        let oy = plan.canvasSize.height * 0.055
        return CIImage(cgImage: pill)
            .transformed(by: CGAffineTransform(translationX: ox, y: oy))
            .composited(over: content)
    }

    private func renderStudioPill(text: String, fontSize: CGFloat) -> CGImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let attr = NSAttributedString(string: trimmed, attributes: attrs)
        let maxW = max(120, plan.canvasSize.width * 0.78)
        let measured = attr.boundingRect(with: CGSize(width: maxW, height: 200),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
        let padX: CGFloat = fontSize * 0.9
        let padY: CGFloat = fontSize * 0.45
        let w = max(44, Int(ceil(measured.width + padX * 2)))
        let h = max(28, Int(ceil(measured.height + padY * 2)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let bgRect = NSRect(x: 0, y: 0, width: w, height: h)
        let path = NSBezierPath(roundedRect: bgRect, xRadius: CGFloat(h) / 2, yRadius: CGFloat(h) / 2)
        NSColor(calibratedWhite: 0.07, alpha: 0.84).setFill()
        path.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.16).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        attr.draw(in: NSRect(x: padX, y: padY, width: measured.width + 2, height: measured.height + 2))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    /// Blurs go into the picture before anything else is drawn on it, so the
    /// zoom magnifies the blur along with what it hides and the pointer still
    /// travels over it. A mosaic under a blur, rather than either alone: blocks
    /// destroy the letters and the blur destroys the blocks.
    private func blurred(_ content: CIImage, at seconds: Double) -> CIImage {
        guard !plan.blurs.isEmpty else { return content }
        // Retiming can hold a source frame between two plan samples. Rounding
        // forward must not uncover that frame before its protected interval
        // ends. Cover both neighboring samples, including either side of cuts.
        // Exact plan times still use just their own sample.
        let position = max(0, seconds) * Double(plan.frameRate)
        let last = max(0, plan.positions.count - 1)
        let lower = min(last, Int(position.rounded(.down)))
        let upper = min(last, Int(position.rounded(.up)))
        var result = content
        for (order, region) in plan.blurs.enumerated() {
            guard plan.blurCovers.indices.contains(order),
                  (lower...upper).contains(where: {
                      plan.blurCovers[order].indices.contains($0)
                          && plan.blurCovers[order][$0]
                  }) else { continue }
            let rect = region.pixelRect(in: plan.sourceSize)
            guard rect.width >= 1, rect.height >= 1 else { continue }
            let block = RecorderSupport.blurBlockSize(for: rect.size, strength: region.strength)
            // Clamped first so the blur never pulls transparent edges in and
            // lets a sliver of the original show through the border.
            let hidden = content.clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: block,
                    kCIInputCenterKey: CIVector(x: rect.minX, y: rect.minY),
                ])
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: block * 0.6,
                ])
                .cropped(to: rect)
            result = hidden.composited(over: result)
        }
        return result
    }

    private func frameIndex(for seconds: Double) -> Int {
        let raw = Int((max(0, seconds) * Double(plan.frameRate)).rounded())
        return min(max(0, raw), max(0, plan.positions.count - 1))
    }

    /// The pointer is drawn into the content, not over the finished frame, so
    /// the zoom carries it along with everything else it magnifies. The click
    /// ring lives in the same space for the same reason.
    private func faded(_ image: CIImage, opacity: Double) -> CIImage {
        guard opacity < 0.999 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
        ])
    }

    private func drawPointer(on content: CIImage, index: Int) -> CIImage {
        let uv = plan.positions[index]
        guard uv.x > -0.2, uv.x < 1.2, uv.y > -0.2, uv.y < 1.2 else { return content }
        let press = plan.pressScale.indices.contains(index) ? plan.pressScale[index] : 1
        // Core Image counts up from the bottom; the track counts down from the
        // top, the way the screen does.
        let x = uv.x * plan.sourceSize.width
        let y = (1 - uv.y) * plan.sourceSize.height

        var result = content
        if plan.showsClickRing, plan.ring.indices.contains(index), plan.ring[index] >= 0 {
            result = drawRing(progress: plan.ring[index],
                              at: CGPoint(x: x, y: y),
                              on: result)
        }

        let shapeIndex = plan.pointerShapeIndex.indices.contains(index)
            ? plan.pointerShapeIndex[index] : 0
        if let sprite = decodedShapes.indices.contains(shapeIndex)
            ? decodedShapes[shapeIndex] : decodedShapes.first ?? nil,
           let shape = plan.pointerShapes.indices.contains(shapeIndex)
            ? plan.pointerShapes[shapeIndex] : plan.pointerShapes.first {
            // The image carries its own point size and its own hot spot, so a
            // text beam or a resize arrow lands exactly where the real one did.
            // One bitmap pixel is one point on screen, so the whole
            // conversion is the scale the plan already resolved.
            let drawnWidth = shape.pointSize.width * plan.pointerScale * CGFloat(press)
            let drawnHeight = shape.pointSize.height * plan.pointerScale * CGFloat(press)
            guard drawnWidth > 0, drawnHeight > 0, sprite.width > 0 else { return result }
            let factor = drawnWidth / CGFloat(sprite.width)
            let hotX = shape.hotSpot.x * plan.pointerScale * CGFloat(press)
            let hotY = shape.hotSpot.y * plan.pointerScale * CGFloat(press)
            let opacity = plan.pointerOpacity.indices.contains(index)
                ? plan.pointerOpacity[index] : 1
            return faded(CIImage(cgImage: sprite)
                .transformed(by: CGAffineTransform(scaleX: factor, y: factor)),
                         opacity: opacity)
                .transformed(by: CGAffineTransform(translationX: x - hotX,
                                                   y: y - drawnHeight + hotY))
                .composited(over: result)
        }

        guard let sprite = fallbackArrow, sprite.width > 0 else { return result }
        let drawn = RecorderCursorSprite.fallbackSize.width * plan.pointerScale * CGFloat(press)
        let factor = drawn / CGFloat(sprite.width)
        let height = CGFloat(sprite.height) * factor
        let hot = CGPoint(x: RecorderCursorSprite.fallbackHotSpot.x * plan.pointerScale
                            * CGFloat(press),
                          y: RecorderCursorSprite.fallbackHotSpot.y * plan.pointerScale
                            * CGFloat(press))
        return CIImage(cgImage: sprite)
            .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            .transformed(by: CGAffineTransform(translationX: x - hot.x, y: y - height + hot.y))
            .composited(over: result)
    }

    private func drawRing(progress: Double, at point: CGPoint, on content: CIImage) -> CIImage {
        let eased = 1 - pow(1 - progress, 3)
        // Tied to the pointer rather than to the frame: the ring belongs to
        // the pointer, so it stays in proportion at any recording size and at
        // whatever pointer size the person chose.
        let unit = plan.pointerPixelSize / 34
        let radius = RecorderMotion.ringRadius * unit * eased
        let width = max(0.6, 2.4 * (1 - progress)) * unit
        let alpha = 0.35 * (1 - progress * progress)
        guard radius > 1, alpha > 0.01,
              let ring = RecorderCursorSprite.ring(radius: radius, lineWidth: width, alpha: alpha)
        else { return content }
        let side = CGFloat(ring.width)
        return CIImage(cgImage: ring)
            .transformed(by: CGAffineTransform(translationX: point.x - side / 2,
                                               y: point.y - side / 2))
            .composited(over: content)
    }

    private func zoomed(_ content: CIImage, index: Int) -> CIImage {
        guard plan.zoom.indices.contains(index) else { return content }
        let z = plan.zoom[index]
        guard z > 1.001, plan.travel.indices.contains(index) else { return content }
        let origin = RecorderMotion.viewportOrigin(travel: plan.travel[index], zoom: z)
        // The viewport is expressed from the top; Core Image measures from the
        // bottom, and the visible height is 1/z of the frame.
        let bottom = 1 - origin.y - 1 / z
        let transform = CGAffineTransform(scaleX: CGFloat(z), y: CGFloat(z))
            .concatenating(CGAffineTransform(
                translationX: -origin.x * plan.sourceSize.width * CGFloat(z),
                y: -bottom * plan.sourceSize.height * CGFloat(z)))
        return content.transformed(by: transform)
            .cropped(to: CGRect(origin: .zero, size: plan.sourceSize))
    }

    private func fitted(_ content: CIImage) -> CIImage {
        guard plan.sourceSize.width > 0, plan.sourceSize.height > 0 else { return content }
        let scaleX = plan.cardRect.width / plan.sourceSize.width
        let scaleY = plan.cardRect.height / plan.sourceSize.height
        return content
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: plan.cardRect.origin.x,
                                               y: plan.cardRect.origin.y))
    }

    // MARK: - Composition

    /// A composition that resamples the recording to a steady frame rate and
    /// renders it through this composer.
    ///
    /// The master is written at a variable rate on purpose, so a still screen
    /// costs nothing while recording; the steady rate is imposed here instead,
    /// in the single decode pass the export already needs.
    ///
    /// Nil when a recording that carries an edit cannot be composed. The plain
    /// path below draws the recording untouched, which is only ever right when
    /// there is nothing drawn on it: answering with it after a failure would
    /// hand back a file missing the areas kept unreadable, and everything else
    /// the person put on the picture.
    static func videoComposition(track: AVAssetTrack,
                                 asset: AVAsset,
                                 duration: CMTime,
                                 frameRate: Int,
                                 composer: RecorderComposer?,
                                 sourceSize: CGSize,
                                 outputSize: CGSize,
                                 playbackSpeed: Double = 1) async -> AVMutableVideoComposition? {
        if let composer {
            await composer.prepareAssets()
            // The handler may run concurrently; this composer only reads
            // immutable state while rendering each frame.
            nonisolated(unsafe) let threadSafeComposer = composer
            let timing = RecorderExportTiming(speed: playbackSpeed)
            let composition = try? await AVMutableVideoComposition.videoComposition(
                with: asset) { request in
                    // Plans are built on the edited, unscaled clock. Map back
                    // before looking up zooms, cursor shapes, captions and
                    // privacy blurs, including frames on either side of a cut.
                    let rendered = threadSafeComposer.render(
                        request.sourceImage,
                        at: timing.sourceTime(forOutputTime: CMTimeGetSeconds(request.compositionTime)))
                    request.finish(with: rendered, context: nil)
                }
            guard let composition else { return nil }
            composition.frameDuration = CMTime(value: 1,
                                               timescale: CMTimeScale(max(1, frameRate)))
            composition.renderSize = composer.canvasSize
            composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
            return composition
        }
        let naturalSize = (try? await track.load(.naturalSize)) ?? sourceSize
        let preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        return plainComposition(track: track,
                                naturalSize: naturalSize,
                                preferredTransform: preferredTransform,
                                outputSize: outputSize,
                                frameRate: frameRate,
                                duration: duration)
    }

    static func plainComposition(track: AVAssetTrack,
                                 naturalSize: CGSize,
                                 preferredTransform: CGAffineTransform,
                                 outputSize: CGSize,
                                 frameRate: Int,
                                 duration: CMTime) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        composition.renderSize = outputSize
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let geometry = RecorderSupport.videoGeometry(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform)
        if geometry.size.width > 0, geometry.size.height > 0 {
            let scale = CGAffineTransform(scaleX: outputSize.width / geometry.size.width,
                                          y: outputSize.height / geometry.size.height)
            layer.setTransform(geometry.transform.concatenating(scale), at: .zero)
        }
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        return composition
    }
}

/// Lazily caches and extracts synced `camera.mov` frames for `RecorderComposer`
/// using bounded 30fps bucket caching and `autoreleasepool` so long exports keep
/// memory flat.
private final class CameraFrameSampler: @unchecked Sendable {
    private let asset: AVURLAsset
    private let generator: AVAssetImageGenerator
    private let lock = NSLock()
    private var prepared = false
    private var hasValidVideo = false
    private var durationSeconds: Double = 0
    private var startOffset: Double = 0
    private var cachedBucket: Int = -1
    private var cachedImage: CGImage?

    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        self.asset = asset
        self.generator = generator
    }

    deinit {
        generator.cancelAllCGImageGeneration()
    }

    func prepare() async {
        let alreadyPrepared = lock.withLock { prepared }
        guard !alreadyPrepared else { return }

        let loadedDuration = (try? await asset.load(.duration).seconds) ?? 0
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        var offset = 0.0
        if let metadata = try? await asset.load(.metadata) {
            for item in metadata where item.identifier == .quickTimeMetadataContentIdentifier {
                if let raw = try? await item.load(.stringValue),
                   raw.hasPrefix("com.vorssaint.recorder.camera.offset:"),
                   let parsed = Double(raw.dropFirst("com.vorssaint.recorder.camera.offset:".count)),
                   parsed.isFinite, parsed >= 0 {
                    offset = parsed
                    break
                }
            }
        }

        lock.withLock {
            prepared = true
            durationSeconds = loadedDuration.isFinite ? max(0, loadedDuration) : 0
            hasValidVideo = durationSeconds > 0.02 && !videoTracks.isEmpty
            startOffset = offset
        }
    }

    private func ensurePreparedSync() {
        let isReady = lock.withLock { prepared }
        guard !isReady else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [weak self] in
            await self?.prepare()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
    }

    func frame(at sourceSeconds: Double) -> CGImage? {
        ensurePreparedSync()
        let (valid, dur, offset) = lock.withLock { (hasValidVideo, durationSeconds, startOffset) }
        guard valid else { return nil }

        let local = max(0, sourceSeconds - offset)
        let clamped = min(max(0, dur - 0.01), local)
        let bucket = max(0, Int((clamped * 30.0).rounded()))

        return lock.withLock { () -> CGImage? in
            if bucket == cachedBucket, let cachedImage {
                return cachedImage
            }
            let semaphore = DispatchSemaphore(value: 0)
            let box = CameraImageBox()
            autoreleasepool {
                generator.generateCGImageAsynchronously(
                    for: CMTime(seconds: clamped, preferredTimescale: 600)
                ) { image, _, _ in
                    box.set(image)
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 0.35)
            }
            let decoded = box.get()
            if let decoded {
                cachedBucket = bucket
                cachedImage = decoded
            }
            return decoded ?? cachedImage
        }
    }
}

private final class CameraImageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CGImage?

    func set(_ image: CGImage?) {
        lock.withLock { stored = image }
    }

    func get() -> CGImage? {
        lock.withLock { stored }
    }
}
