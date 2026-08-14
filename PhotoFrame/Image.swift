//
//  Image.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 30/09/2024.
//

import Foundation
import AppKit

/// Save NSImage to file given by URL
func saveImage(_ image: NSImage, format: Format, quality: Double, file: String) -> Bool {
    // Get output format details
    let (ext, repr) = switch format {
    case .jpg: (".jpg", NSBitmapImageRep.FileType.jpeg)
    case .png: (".png", NSBitmapImageRep.FileType.png)
    }

    // Build URL for file
    let url = URL(filePath: file + ext)

    // Convert to CGImage
    guard
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        print("ERROR: Failed to create cgImage from NSImage")
        return false
    }

    // Get NSBitmapImageRep from CGImage
    let newRep = NSBitmapImageRep(cgImage: cgImage)

    // Output size in pixels, 1:1 with the pixel data. Using the source NSImage's `size`
    // (which is in points) instead can silently mismatch the actual pixel dimensions under
    // a Retina scale factor, so it's derived directly from the CGImage here instead.
    newRep.size = CGSize(width: cgImage.width, height: cgImage.height)

    // Compression quality only applies to JPEG output
    var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
    if format == .jpg {
        properties[.compressionFactor] = quality
    }

    // Convert to target image type
    guard
        let imgData = newRep.representation(using: repr, properties: properties)
    else {
        print("ERROR: Failed to create output image from NSBitmapImageRep")
        return false
    }

    // Write to the output file
    do {
        try imgData.write(to: url)
    } catch {
        print("ERROR: Failed to save \(url): \(error)")
        return false
    }

    return true
}
