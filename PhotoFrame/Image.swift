//
//  Image.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 30/09/2024.
//

import Foundation
import AppKit

/// Save NSImage to file given by URL
func saveImage(_ image: NSImage, format: Format, file: String) -> Bool {
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

    // Output size = input size
    newRep.size = image.size

    // Convert to target image type
    guard
        let imgData = newRep.representation(using: repr, properties: [:])
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
