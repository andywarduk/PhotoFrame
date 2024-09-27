//
//  PhotoFrame.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 23/09/2024.
//

import Foundation
import Photos
import ArgumentParser
import AppKit

enum Format: String, ExpressibleByArgument {
    case png, jpg
}

enum Naming: String, ExpressibleByArgument {
    case date, id
}

@main
struct Args: ParsableCommand {
    @Option(name: [.short, .customLong("width")], help: "Width of the images to generate")
    var width: UInt
    
    @Option(name: [.short, .customLong("height")], help: "Height of the images to generate")
    var height: UInt
    
    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output")
    var verbose: Bool = false

    @Flag(name: [.short, .customLong("flatten")], help: "Single directory level in the output directory")
    var flatten: Bool = false

    @Option(name: [.customShort("r"), .customLong("skip")], help: "Skip album path matching regular expression")
    var skipAlbumRe: [String] = []

    @Argument(help: "Output directory")
    var outputDir: String
    
    @Option(name: [.customShort("f"), .customLong("format")], help: "Output image format")
    var format: Format = .jpg

    @Option(name: [.customShort("n"), .customLong("naming")], help: "Image file name format")
    var naming: Naming = .date

    func run() throws {
        // Build skip regular expressions
        var skipRe: Array<Regex<AnyRegexOutput>> = []
        
        // Add regular expression skips
        for skip in self.skipAlbumRe {
            do {
                let re = try Regex(skip);
                skipRe.append(re)
            } catch {
                print("Regular expression '\(skip)' is not valid: \(error)")
                return
            }
        }

        // Work out target aspect ratio
        let targetAspect: Double = Double(width) / Double(height)
        
        // Start async main
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            let state = State(
                args: self,
                targetAspect: targetAspect,
                imgmgr: PHImageManager.default(),
                skipRe: skipRe
            )
            
            await AsyncMain(state: state)
            
            semaphore.signal()
        }
        
        semaphore.wait()
    }
}

struct State {
    var args: Args
    var targetAspect: Double
    var imgmgr: PHImageManager
    var skipRe: [Regex<AnyRegexOutput>]
}

func AsyncMain(state: State) async {
    if state.args.verbose {
        print("Getting authorisation...")
    }
    
    if await GetAuth() {
        if state.args.verbose {
            print("Processing collections...")
        }
        
        await Process(state: state)
    }
}

func Process(state: State) async {
    // Get top level collections
    let coll = PHCollection.fetchTopLevelUserCollections(with: nil)
    
    // Walk the result
    let walkState = WalkState()
    WalkColl(coll: coll, state: state, walkState: walkState)
}

class WalkState {
    private var names: Array<String> = Array()
    private var pathcomp: Array<String> = Array()

    /// Copies this walkstate to another
    func copy() -> WalkState {
        let new = WalkState()

        new.names = names
        new.pathcomp = pathcomp

        return new
    }
    
    /// Pushes a collection name on to the stack
    func add(name: Optional<String>, id: String) {
        let name = name ?? id
        names.append(name)
        pathcomp.append(name.replacingOccurrences(of: "/", with: "_", options: .literal, range: nil))
    }

    /// Builds full path using collection names on the stack
    func path() -> String {
        return pathcomp.joined(separator: "/")
    }
}

/// Walks the child nodes in a Photo Libraey collection and processes if not already processed and not skipped
func WalkColl(coll: PHFetchResult<PHCollection>, state: State, walkState: WalkState) -> Void {
    coll.enumerateObjects() { coll, int, ptr in
        // Create new walk state for this item
        let curWalkState = walkState.copy()
        curWalkState.add(name: coll.localizedTitle, id: coll.localIdentifier)

        // Calculate path
        let path = curWalkState.path()

        // Skip this collection?
        if !state.skipRe.isEmpty {
            for skip in state.skipRe {
                do {
                    if try skip.wholeMatch(in: path) != nil {
                        if state.args.verbose {
                            print("Skipping \(path) (on command line skip list)")
                        }
    
                        return
                    }
                } catch {
                    print("Caught error testing regex: \(error)")
                }
            }
        }
        
        if coll.canContainAssets {
            // Calculate file system directory
            let dir = if state.args.flatten {
                state.args.outputDir.appending("/" + path.replacingOccurrences(of: "/", with: "_"))
            } else {
                state.args.outputDir.appending("/" + path)
            }
            
            // If directory already exists then skip
            if FileManager.default.fileExists(atPath: dir) {
                if state.args.verbose {
                    print("Skipping \(path) (directory \(dir) already exists)")
                }
            } else {
                // Process assets in this collection
                if state.args.verbose {
                    print("Processing assets in \(path)")
                }

                ProcessAssets(coll: coll, state: state, dir: dir)
            }
        }
        
        if coll.canContainCollections {
            // Process collections in this collection
            if state.args.verbose {
                print("Processing collections in \(path)")
            }
            
            let next = PHCollection.fetchCollections(in: coll as! PHCollectionList, options: nil)
            WalkColl(coll: next, state: state, walkState: curWalkState)
        }
    }
}

/// Fetches the assets from a collection and processes
func ProcessAssets(coll: PHCollection, state: State, dir: String) {
    // Set up fetch options
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    options.includeAllBurstAssets = false
    options.includeHiddenAssets = false
    
    // Fetch collection assets
    let assets = PHAsset.fetchAssets(in: coll as! PHAssetCollection, options: options)

    // Walk the assets
    WalkAssets(assets: assets, state: state, dir: dir)
}

/// Walks a list of photo library assets, checks if the aspect ratio is compatible with the output and processes
func WalkAssets(assets: PHFetchResult<PHAsset>, state: State, dir: String) -> Void {
    assets.enumerateObjects { asset, int, ptr in
        if CheckAsset(asset: asset, state: state) {
            ProcessAsset(asset: asset, state: state, dir: dir)
        }
    }
}

func CheckAsset(asset: PHAsset, state: State) -> Bool {
    let assetDesc = "\(asset.localIdentifier) size \(asset.pixelWidth)x\(asset.pixelHeight)"
    
    // Calculate the aspect ratio of the image
    let aspect = Double(asset.pixelWidth) / Double(asset.pixelHeight)

    func checkTooTall() -> Bool {
        if (Double(asset.pixelHeight) * (Double(state.args.width) / Double(asset.pixelWidth))) > (2.0 * Double(state.args.height)) {
            // Asset is too tall
            if state.args.verbose {
                print("Skipping asset \(assetDesc) (too tall)")
            }

            return false
        }
        
        return true
    }
    
    func checkTooWide() -> Bool {
        if (Double(asset.pixelWidth) * (Double(state.args.height) / Double(asset.pixelHeight))) > (2.0 * Double(state.args.width)) {
            // Asset is too wide
            if state.args.verbose {
                print("Skipping asset \(assetDesc) (too wide)")
            }

            return false
        }

        return true
    }

    // Check aspect ratio of the image
    if state.targetAspect < 1 {
        // Want portrait
        if aspect > 1 {
            // Asset is landscape
            if state.args.verbose {
                print("Skipping asset \(assetDesc) (landscape)")
            }
            
            return false
        }
        
        if !checkTooTall() {
            return false
        }
    } else if state.targetAspect > 1 {
        // Want landscape
        if aspect < 1 {
            // Asset is portrait
            if state.args.verbose {
                print("Skipping asset \(assetDesc) (portrait)")
            }

            return false
        }
        
        if !checkTooWide() {
            return false
        }
    } else {
        // Want square
        if aspect < 1 {
            // Asset is portrait
            if !checkTooTall() {
                return false
            }
        } else {
            // Asset is landscape / square
            if !checkTooWide() {
                return false
            }
        }
    }
    
    if state.args.verbose {
        print("Processing asset \(assetDesc)")
    }

    return true
}

/// Converts a photo library asset to an image and saves it
func ProcessAsset(asset: PHAsset, state: State, dir: String) {
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
    state.imgmgr.requestImage(for: asset, targetSize: size, contentMode: .aspectFill , options: options, resultHandler: { (data, info) in
        // Got image data?
        if let data = data {
            // Does the directory exist?
            if !FileManager.default.fileExists(atPath: dir) {
                // Create URL for directory
                let dirUrl = URL(filePath: dir, directoryHint: .isDirectory, relativeTo: nil)
                
                // Try and create the directory
                do{
                    try FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print("ERROR: Failed to create directory \(dirUrl)", dirUrl, error)
                    return
                }
            }
            
            // Work out target file name stub
            let fileStub = switch state.args.naming {
            case .date: (asset.creationDate ?? Date()).ISO8601Format(Date.ISO8601FormatStyle())
            case .id: asset.localIdentifier
            }

            // Build target path
            let file = dir.appending("/" + fileStub.replacingOccurrences(of: "/", with: "_"))

            // Save the image at the file
            if saveImage(data, format: state.args.format, file: file) {
                if state.args.verbose {
                    print("Image saved to \(fileStub)")
                }
            }
        } else {
            // Failed to retrieve image
            print("ERROR: No image returned for \(asset.localIdentifier)")
        }
    })
}

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
    }
    catch {
        print("ERROR: Failed to save \(url): \(error)")
        return false
    }
    
    return true
}

/// Get authorisation to access the photos library
func GetAuth() async -> Bool {
    // Get authorisation status
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    if status == .notDetermined {
        // Not determined - so request it
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    if status == .authorized {
        // Authorised for access
        return true
    }

    // Not authorised for access
    switch status {
        case .notDetermined: print("Photo library authorisation could not be determined")
        case .denied: print("Access to photo library is denied")
        case .restricted: print("Access to photo library is restricted")
        case .limited: print("Access to photo library is limited")
        default: print("Unknown photo library authorisation status", status)
    }

    return false
}
