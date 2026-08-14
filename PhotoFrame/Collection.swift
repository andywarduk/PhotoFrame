//
//  Collection.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 30/09/2024.
//

import Foundation
import Photos
import AppKit

/// Name of the marker file written into an output directory while a collection is
/// being processed, and removed once processing completes successfully. A directory
/// is only treated as done if it exists and has no marker, so an interrupted run
/// leaves a directory that will be retried rather than skipped forever.
private let inflightMarkerName = ".photoframe-inflight"

private struct WalkState {
    private var pathcomp: [String] = []

    /// Returns a copy of this walk state with an additional collection name pushed on to the stack
    func adding(name: String?, id: String) -> WalkState {
        var new = self
        let name = name ?? id
        new.pathcomp.append(name.replacingOccurrences(of: "/", with: "_", options: .literal, range: nil))
        return new
    }

    /// Builds full path using collection names on the stack
    func path() -> String {
        return pathcomp.joined(separator: "/")
    }
}

/// Starts a collection walk from the top level collections in the photo library
func processTopLevelCollections(state: State) async {
    // Initialise walk state
    let walkState = WalkState()

    // Get top level collections
    let coll = PHCollection.fetchTopLevelUserCollections(with: nil)

    // Walk the result
    walkCollection(coll: coll, state: state, walkState: walkState)
}

/// Walks the child nodes in a Photo Libraey collection and processes if not already processed and not skipped
private func walkCollection(coll: PHFetchResult<PHCollection>, state: State, walkState: WalkState) {
    // Tracks how many times each sibling name has been seen at this level, so that
    // collections sharing a name don't collide on the same output path
    var seenNames: [String: Int] = [:]

    coll.enumerateObjects { coll, _, _ in
        let baseName = coll.localizedTitle ?? coll.localIdentifier
        let occurrence = seenNames[baseName, default: 0]
        seenNames[baseName] = occurrence + 1

        let disambiguatedName = occurrence == 0 ? baseName : "\(baseName) (\(occurrence + 1))"

        // Create new walk state for this item
        let curWalkState = walkState.adding(name: disambiguatedName, id: coll.localIdentifier)

        // Calculate path
        let path = curWalkState.path()

        // Skip this collection?
        if skipCollection(state: state, path: path) {
            return
        }

        // Does the collection contain assets?
        if coll.canContainAssets {
            // Calculate file system directory
            let dir = if state.args.flatten {
                state.args.outputDir.appending("/" + path.replacingOccurrences(of: "/", with: "_"))
            } else {
                state.args.outputDir.appending("/" + path)
            }

            let markerFile = dir.appending("/" + inflightMarkerName)

            let alreadyComplete = FileManager.default.fileExists(atPath: dir)
                && !FileManager.default.fileExists(atPath: markerFile)

            // If this collection was already fully processed on a previous run then skip it
            if alreadyComplete {
                if state.args.verbose {
                    print("Skipping \(path) (already processed, \(dir) is complete)")
                }
            } else {
                // Process assets in this collection
                if state.args.verbose {
                    print("Processing assets in \(path)")
                }

                if let coll = coll as? PHAssetCollection {
                    beginProcessing(dir: dir, markerFile: markerFile)
                    processAssets(coll: coll, state: state, dir: dir)
                    finishProcessing(markerFile: markerFile)
                } else {
                    print("ERROR: Can't cast collection to PHAssetCollection")
                }
            }
        }

        // Does the collection contain other collections?
        if coll.canContainCollections {
            // Process collections in this collection
            if state.args.verbose {
                print("Processing collections in \(path)")
            }

            if let coll = coll as? PHCollectionList {
                let next = PHCollection.fetchCollections(in: coll, options: nil)
                walkCollection(coll: next, state: state, walkState: curWalkState)
            } else {
                print("ERROR: Can't cast collection to PHCollectionList")
            }
        }
    }
}

/// Marks a collection's output directory as in-flight, creating the directory first
/// if it doesn't already exist (e.g. no matching assets found yet, or a fresh run)
private func beginProcessing(dir: String, markerFile: String) {
    if !FileManager.default.fileExists(atPath: dir) {
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("ERROR: Failed to create directory \(dir): \(error)")
            return
        }
    }

    if !FileManager.default.createFile(atPath: markerFile, contents: nil) {
        print("ERROR: Failed to write in-flight marker \(markerFile)")
    }
}

/// Clears the in-flight marker once a collection has finished processing successfully
private func finishProcessing(markerFile: String) {
    if FileManager.default.fileExists(atPath: markerFile) {
        do {
            try FileManager.default.removeItem(atPath: markerFile)
        } catch {
            print("ERROR: Failed to remove in-flight marker \(markerFile): \(error)")
        }
    }
}

private func skipCollection(state: State, path: String) -> Bool {
    if !state.skipRe.isEmpty {
        for skip in state.skipRe {
            do {
                if try skip.wholeMatch(in: path) != nil {
                    if state.args.verbose {
                        print("Skipping \(path) (on command line skip list)")
                    }

                    return true
                }
            } catch {
                print("Caught error testing regex: \(error)")
            }
        }
    }

    return false
}
