//
//  Asset.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 30/09/2024.
//

import Foundation
import Photos

extension PHAsset {
    /// Returns a description of the asset suitable for output
    func assetDescription() -> String {
        return "\(self.localIdentifier) size \(self.pixelWidth)x\(self.pixelHeight)"
    }

    /// Aspect ratio of the asset (width / height)
    var aspectRatio: Double {
        Double(self.pixelWidth) / Double(self.pixelHeight)
    }
}

/// Fetches the assets from a collection and processes them concurrently
func processAssets(coll: PHAssetCollection, state: State, dir: String) {
    // Set up fetch options
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    options.includeAllBurstAssets = false
    options.includeHiddenAssets = false

    // Fetch collection assets
    let assets = PHAsset.fetchAssets(in: coll, options: options)

    // Guards directory creation below against races between concurrently processed assets.
    // PHImageManager's synchronous requestImage is safe to call concurrently, so assets are
    // processed in parallel via concurrentPerform; this call blocks until every asset in the
    // collection has been handled, so it's still safe for the caller to treat processAssets
    // as synchronous (e.g. to write a completion marker afterwards).
    let dirLock = NSLock()

    DispatchQueue.concurrentPerform(iterations: assets.count) { index in
        let asset = assets.object(at: index)

        guard state.assetCheck(asset, state) else {
            return
        }

        if state.args.verbose {
            print("Processing asset \(asset.assetDescription())")
        }

        processAsset(asset: asset, state: state, dir: dir, dirLock: dirLock)
    }
}

/// Checks an asset is portrait and not too tall
func checkAssetPortrait(asset: PHAsset, state: State) -> Bool {
    if asset.aspectRatio > 1 {
        // Asset is landscape
        if state.args.verbose {
            print("Skipping asset \(asset.assetDescription()) (landscape)")
        }

        return false
    }

    return checkTooTall(asset: asset, state: state)
}

/// Checks an asset is landscape and not too wide
func checkAssetLandscape(asset: PHAsset, state: State) -> Bool {
    if asset.aspectRatio < 1 {
        // Asset is portrait
        if state.args.verbose {
            print("Skipping asset \(asset.assetDescription()) (portrait)")
        }

        return false
    }

    return checkTooWide(asset: asset, state: state)
}

/// Checks an asset will fit a square frame
func checkAssetSquare(asset: PHAsset, state: State) -> Bool {
    if asset.aspectRatio < 1 {
        // Asset is portrait - check it's not too tall
        return checkTooTall(asset: asset, state: state)
    } else {
        // Asset is landscape / square - check it's not too wide
        return checkTooWide(asset: asset, state: state)
    }
}

/// Checks if an asset is too tall
private func checkTooTall(asset: PHAsset, state: State) -> Bool {
    if (Double(asset.pixelHeight) * (Double(state.args.width) / Double(asset.pixelWidth)))
        > (state.args.maxMultiple * Double(state.args.height)) {
        // Asset is too tall
        if state.args.verbose {
            print("Skipping asset \(asset.assetDescription()) (too tall)")
        }

        return false
    }

    return true
}

/// Checks if an asset is too wide
private func checkTooWide(asset: PHAsset, state: State) -> Bool {
    if (Double(asset.pixelWidth) * (Double(state.args.height) / Double(asset.pixelHeight)))
        > (state.args.maxMultiple * Double(state.args.width)) {
        // Asset is too wide
        if state.args.verbose {
            print("Skipping asset \(asset.assetDescription()) (too wide)")
        }

        return false
    }

    return true
}

/// Converts a photo library asset to an image and saves it
private func processAsset(asset: PHAsset, state: State, dir: String, dirLock: NSLock) {
    // Build target CGSize
    let size = CGSize(width: Double(state.args.width), height: Double(state.args.height))

    // Set up image rerieval options
    let options = PHImageRequestOptions()
    options.version = .current
    options.resizeMode = .exact
    options.deliveryMode = .highQualityFormat
    options.isNetworkAccessAllowed = true
    options.isSynchronous = true
    options.allowSecondaryDegradedImage = true

    // Request the image
    PHImageManager.default().requestImage(
        for: asset, targetSize: size, contentMode: .aspectFill, options: options
    ) { data, _ in
        // Got image data?
        if let data = data {
            if let file = assetPath(asset: asset, state: state, dir: dir, dirLock: dirLock) {
                // Save the image at the file
                if saveImage(data, format: state.args.format, quality: state.args.quality, file: file) {
                    if state.args.verbose {
                        print("Image saved to \(file)")
                    }
                }
            }
        } else {
            // Failed to retrieve image
            print("ERROR: No image returned for \(asset.localIdentifier)")
        }
    }
}

private func assetPath(asset: PHAsset, state: State, dir: String, dirLock: NSLock) -> String? {
    // Directory creation is shared across concurrently processed assets in the same
    // collection, so it must be serialized to avoid a race between the exists-check and create
    dirLock.lock()
    defer { dirLock.unlock() }

    // Does the directory exist?
    if !FileManager.default.fileExists(atPath: dir) {
        // Create URL for directory
        let dirUrl = URL(filePath: dir, directoryHint: .isDirectory, relativeTo: nil)

        // Try and create the directory
        do {
            try FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("ERROR: Failed to create directory \(dirUrl)", dirUrl, error)
            return nil
        }
    }

    // Work out target file name stub
    let fileStub = switch state.args.naming {
    case .date: (asset.creationDate ?? Date()).ISO8601Format(Date.ISO8601FormatStyle())
    case .id: asset.localIdentifier
    }

    // Build target path
    return dir.appending("/" + fileStub.replacingOccurrences(of: "/", with: "_"))
}
