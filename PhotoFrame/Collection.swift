//
//  Collection.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 30/09/2024.
//

import Foundation
import Photos
import AppKit

private class WalkState {
    private var names: [String] = []
    private var pathcomp: [String] = []

    /// Copies this walkstate to another
    func copy() -> WalkState {
        let new = WalkState()

        new.names = names
        new.pathcomp = pathcomp

        return new
    }

    /// Pushes a collection name on to the stack
    func add(name: String?, id: String) {
        let name = name ?? id
        names.append(name)
        pathcomp.append(name.replacingOccurrences(of: "/", with: "_", options: .literal, range: nil))
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
    coll.enumerateObjects { coll, _, _ in
        // Create new walk state for this item
        let curWalkState = walkState.copy()
        curWalkState.add(name: coll.localizedTitle, id: coll.localIdentifier)

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

                if let coll = coll as? PHAssetCollection {
                    processAssets(coll: coll, state: state, dir: dir)
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
