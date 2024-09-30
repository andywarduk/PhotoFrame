//
//  Asset.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 30/09/2024.
//

import Photos

/// Maximum size multiple to allow
let maxMultiple: Double = 2.0

extension PHAsset {
    /// Returns a description of the asset suitable for output
    func assetDescription() -> String {
        return "\(self.localIdentifier) size \(self.pixelWidth)x\(self.pixelHeight)"
    }
}

/// Fetches the assets from a collection and processes
func processAssets(coll: PHAssetCollection, state: State, dir: String) {
    // Set up fetch options
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    options.includeAllBurstAssets = false
    options.includeHiddenAssets = false

    // Fetch collection assets
    let assets = PHAsset.fetchAssets(in: coll, options: options)

    // Walk the assets
    assets.enumerateObjects { asset, _, _ in
        if state.assetCheck(asset, state) {
            if state.args.verbose {
                print("Processing asset \(asset.assetDescription())")
            }

            processAsset(asset: asset, state: state, dir: dir)
        }
    }
}

/// Checks an asset is portrait and not too tall
func checkAssetPortrait(asset: PHAsset, state: State) -> Bool {
    // Calculate the aspect ratio of the image
    let aspect = Double(asset.pixelWidth) / Double(asset.pixelHeight)

    if aspect > 1 {
        // Asset is landscape
        if state.args.verbose {
            print("Skipping asset \(asset.assetDescription()) (landscape)")
        }

        return false
    }

    // Check it's not too tall
    if !checkTooTall(asset: asset, state: state) {
        return false
    }

    return true
}

/// Checks an asset is landscape and not too wide
func checkAssetLandscape(asset: PHAsset, state: State) -> Bool {
    // Calculate the aspect ratio of the image
    let aspect = Double(asset.pixelWidth) / Double(asset.pixelHeight)

    if aspect < 1 {
        // Asset is portrait
        if state.args.verbose {
            print("Skipping asset \(asset.assetDescription()) (portrait)")
        }

        return false
    }

    // Check it's not too wide
    if !checkTooWide(asset: asset, state: state) {
        return false
    }

    return true
}

/// Checks an asset will fit a square frame
func checkAssetSquare(asset: PHAsset, state: State) -> Bool {
    // Calculate the aspect ratio of the image
    let aspect = Double(asset.pixelWidth) / Double(asset.pixelHeight)

    // Want square
    if aspect < 1 {
        // Asset is portrait - check it's not too tall
        if !checkTooTall(asset: asset, state: state) {
            return false
        }
    } else {
        // Asset is landscape / square - check it's not too wide
        if !checkTooWide(asset: asset, state: state) {
            return false
        }
    }

    return true
}

/// Checks if an asset is too tall
private func checkTooTall(asset: PHAsset, state: State) -> Bool {
    if (Double(asset.pixelHeight) * (Double(state.args.width) / Double(asset.pixelWidth)))
        > (maxMultiple * Double(state.args.height)) {
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
        > (maxMultiple * Double(state.args.width)) {
        // Asset is too wide
        if state.args.verbose {
            print("Skipping asset \(asset.assetDescription()) (too wide)")
        }

        return false
    }

    return true
}

/// Converts a photo library asset to an image and saves it
private func processAsset(asset: PHAsset, state: State, dir: String) {
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
            if let file = assetPath(asset: asset, state: state, dir: dir) {
                // Save the image at the file
                if saveImage(data, format: state.args.format, file: file) {
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

private func assetPath(asset: PHAsset, state: State, dir: String) -> String? {
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
