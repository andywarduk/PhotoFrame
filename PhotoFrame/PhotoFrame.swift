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

@main
struct Args: ParsableCommand {
    @Option(name: [.short, .customLong("width")], help: "Width of the images to generate")
    var width: UInt
    
    @Option(name: [.short, .customLong("height")], help: "Height of the images to generate")
    var height: UInt
    
    @Flag(name: [.short, .customLong("verbose")], help: "Verbose output")
    var verbose: Bool = false

    @Option(name: [.short, .customLong("skip")], help: "Skip album path")
    var skipAlbum: [String] = []

    @Option(name: [.customShort("r"), .customLong("skipre")], help: "Skip album path matching regular expression")
    var skipAlbumRe: [String] = []

    @Argument(help: "Output directory")
    var outputDir: String
    
    func run() throws {
        // Build skip regular expressions
        var skipRe: Array<Regex<AnyRegexOutput>> = []
        
        // Add literal skips
        for skip in self.skipAlbumRe {
            skipRe.append(Regex(verbatim: skip))
        }
        
        // Add regular expression skips
        for skip in self.skipAlbumRe {
            do {
                let re = try Regex(skip);
                skipRe.append(re)
            } catch {
                print("Regular expression \(skip) is not valid: \(error)")
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
        
        // Calculate file system directory
        let dir = state.args.outputDir.appending("/" + path)
        
        // If directory already exists then skip
        if FileManager.default.fileExists(atPath: dir) {
            if state.args.verbose {
                print("Skipping \(path) (directory \(dir) already exists)")
            }
            
            return
        }

        if state.args.verbose {
            print("Processing \(path)")
        }
        
        if coll.canContainAssets {
            // Process assets in this collection
            ProcessAssets(coll: coll, state: state, dir: dir)
        }
        
        if coll.canContainCollections {
            // Process collections in this collection
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
        // Calculate the aspect ratio of the image
        let aspect = Double(asset.pixelWidth) / Double(asset.pixelHeight)

        // Check aspect ratio of the image
        if state.targetAspect < 1 {
            // Want portrait
            if aspect > 1 {
                if state.args.verbose {
                    print("Skipping asset", asset.localIdentifier, "(landscape)")
                }
                
                return
            }
        } else if state.targetAspect > 1 {
            // Want landscape
            if aspect < 1 {
                if state.args.verbose {
                    print("Skipping asset", asset.localIdentifier, "(portrait)")
                }

                return
            }
        } else {
            // Want square - accept all
        }
        
        if state.args.verbose {
            print("Processing asset", asset.localIdentifier, "size", asset.pixelWidth, "x", asset.pixelHeight)
        }

        ProcessAsset(asset: asset, state: state, dir: dir)
    }
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
            // Work out target file name
            let file = dir.appending("/" + asset.localIdentifier.replacingOccurrences(of: "/", with: "_") + ".png")

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
            
            // Build URL for file
            let fileUrl = URL(filePath: file)
            
            // Save the image at the file URL
            if saveImage(data, atUrl: fileUrl) {
                if state.args.verbose {
                    print("Image saved to \(file)")
                }
            }
        } else {
            // Failed to retrieve image
            print("ERROR: No image returned for \(asset.localIdentifier)")
        }
    })
}

/// Save NSImage to file given by URL
func saveImage(_ image: NSImage, atUrl url: URL) -> Bool {
    guard
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        print("ERROR: Failed to create cgImage from NSImage")
        return false
    }
    
    let newRep = NSBitmapImageRep(cgImage: cgImage)
    
    newRep.size = image.size
    
    guard
        let pngData = newRep.representation(using: .png, properties: [:])
    else {
        print("ERROR: Failed to create png from NSBitmapImageRep")
        return false
    }

    do {
        try pngData.write(to: url)
    }
    catch {
        print("ERROR: Failed to save \(url): \(error)")
        return false
    }
    
    return true
}

/// Get authorisation to access the photos library
func GetAuth() async -> Bool {
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    if status == .notDetermined {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    switch status {
        case .authorized: print("Authorized")
        case .notDetermined: print("Authorisation could not be determined")
        case .denied: print("Access to photos library is denied")
        case .restricted: print("Access to photos library is restricted")
        case .limited: print("Access to photos library is limited")
        default: print("Unknown authorisation status", status)
    }

    return status == .authorized
}
