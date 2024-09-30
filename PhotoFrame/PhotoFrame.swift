//
//  PhotoFrame.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 23/09/2024.
//

import ArgumentParser
import AppKit
import Photos

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

    @Flag(name: [.customShort("F"), .customLong("flatten")], help: "Single directory level in the output directory")
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
        var skipRe: [Regex<AnyRegexOutput>] = []

        // Add regular expression skips
        for skip in self.skipAlbumRe {
            do {
                let regex = try Regex(skip)
                skipRe.append(regex)
            } catch {
                print("Regular expression '\(skip)' is not valid: \(error)")
                return
            }
        }

        // Work out target aspect ratio
        let targetAspect: Double = Double(width) / Double(height)

        // Work out function to check asset size
        let assetCheckFn = if targetAspect < 1 {
            checkAssetPortrait
        } else if targetAspect > 1 {
            checkAssetLandscape
        } else {
            checkAssetSquare
        }

        // Start async main
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            let state = State(
                args: self,
                targetAspect: targetAspect,
                skipRe: skipRe,
                assetCheck: assetCheckFn
            )

            await asyncMain(state: state)

            semaphore.signal()
        }

        semaphore.wait()
    }
}

struct State {
    var args: Args
    var targetAspect: Double
    var skipRe: [Regex<AnyRegexOutput>]
    var assetCheck: (PHAsset, State) -> Bool
}

func asyncMain(state: State) async {
    if state.args.verbose {
        print("Getting authorisation...")
    }

    if await getAuth() {
        if state.args.verbose {
            print("Processing collections...")
        }

        await processTopLevelCollections(state: state)
    }
}
