// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ShelfProImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case webp
    case heic

    var id: String { rawValue }

    var utTypeIdentifier: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .webp: return UTType(filenameExtension: "webp")?.identifier ?? "org.webmproject.webp"
        case .heic: return "public.heic"
        }
    }

    var fileExtension: String { rawValue }
}

/// Pro batch file actions for the Drop Shelf (WebP/HEIC image conversion, PDF merge, batch rename).
enum ShelfProActions {
    enum ActionError: Error, Equatable {
        case unreadableImage
        case writeFailed
        case emptyInput
        case collisionDetected
    }

    struct RenamePreviewItem: Equatable, Sendable {
        let sourceURL: URL
        let targetName: String
        let hasCollision: Bool
    }

    static func convertAndResizeImage(at sourceURL: URL,
                                      to format: ShelfProImageFormat,
                                      maxDimension: Int? = nil,
                                      quality: Double = 0.85,
                                      outputDirectory: URL? = nil) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ActionError.unreadableImage
        }

        let targetCG = resizeIfNeeded(cgImage, maxDimension: maxDimension)
        let supportedTypes = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let chosenUTI: String
        let chosenExt: String
        if supportedTypes.contains(format.utTypeIdentifier) {
            chosenUTI = format.utTypeIdentifier
            chosenExt = format.fileExtension
        } else {
            // Safe host fallback if WebP/HEIC encoder codec is unavailable.
            chosenUTI = "public.png"
            chosenExt = "png"
        }

        let folder = outputDirectory ?? sourceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent("\(baseName)-converted.\(chosenExt)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName)-converted-\(suffix).\(chosenExt)")
            suffix += 1
        }

        guard let destination = CGImageDestinationCreateWithURL(candidate as CFURL, chosenUTI as CFString, 1, nil) else {
            throw ActionError.writeFailed
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.1), 1.0)]
        CGImageDestinationAddImage(destination, targetCG, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ActionError.writeFailed
        }
        return candidate
    }

    private static func resizeIfNeeded(_ image: CGImage, maxDimension: Int?) -> CGImage {
        guard let maxDim = maxDimension, maxDim > 0 else { return image }
        let width = image.width
        let height = image.height
        let longest = max(width, height)
        guard longest > maxDim else { return image }
        let scale = Double(maxDim) / Double(longest)
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))
        guard let ctx = CGContext(data: nil,
                                  width: newWidth,
                                  height: newHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return ctx.makeImage() ?? image
    }

    @discardableResult
    static func mergePDFs(at urls: [URL], outputURL: URL) throws -> Int {
        guard !urls.isEmpty else { throw ActionError.emptyInput }
        let merged = PDFDocument()
        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for pageIndex in 0..<doc.pageCount {
                if let page = doc.page(at: pageIndex) {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        guard merged.pageCount > 0 else { throw ActionError.writeFailed }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard merged.write(to: outputURL) else {
            throw ActionError.writeFailed
        }
        return merged.pageCount
    }

    static func previewBatchRename(urls: [URL],
                                   prefix: String,
                                   startIndex: Int = 1,
                                   find: String = "",
                                   replace: String = "") -> [RenamePreviewItem] {
        var seenNames = Set<String>()
        return urls.enumerated().map { offset, url in
            let ext = url.pathExtension
            let origStem = url.deletingPathExtension().lastPathComponent
            var newStem: String
            if !prefix.isEmpty {
                newStem = "\(prefix)_\(startIndex + offset)"
            } else if !find.isEmpty {
                newStem = origStem.replacingOccurrences(of: find, with: replace)
            } else {
                newStem = origStem
            }
            let targetName = ext.isEmpty ? newStem : "\(newStem).\(ext)"
            let collision = !seenNames.insert(targetName.lowercased()).inserted
            return RenamePreviewItem(sourceURL: url, targetName: targetName, hasCollision: collision)
        }
    }

    @discardableResult
    static func applyBatchRename(_ items: [RenamePreviewItem], fileManager: FileManager = .default) throws -> [URL] {
        if items.contains(where: \.hasCollision) {
            throw ActionError.collisionDetected
        }
        var outputs: [URL] = []
        for item in items {
            let dest = item.sourceURL.deletingLastPathComponent().appendingPathComponent(item.targetName)
            if dest != item.sourceURL {
                if fileManager.fileExists(atPath: dest.path) {
                    throw ActionError.collisionDetected
                }
                try fileManager.moveItem(at: item.sourceURL, to: dest)
            }
            outputs.append(dest)
        }
        return outputs
    }
}
