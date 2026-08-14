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
struct Args: AsyncParsableCommand {
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

    @Option(
        name: [.customShort("m"), .customLong("max-multiple")],
        help: "Maximum aspect ratio multiple to allow before an asset is skipped as too tall/wide"
    )
    var maxMultiple: Double = 2.0

    @Option(
        name: [.customShort("q"), .customLong("quality")],
        help: "JPEG compression quality from 0.0 to 1.0 (ignored for png)"
    )
    var quality: Double = 1.0

    func validate() throws {
        guard width > 0 else {
            throw ValidationError("Width must be greater than 0")
        }

        guard height > 0 else {
            throw ValidationError("Height must be greater than 0")
        }

        guard maxMultiple > 0 else {
            throw ValidationError("Max multiple must be greater than 0")
        }

        guard quality >= 0 && quality <= 1 else {
            throw ValidationError("Quality must be between 0.0 and 1.0")
        }
    }

    func run() async throws {
        // Build skip regular expressions
        var skipRe: [Regex<AnyRegexOutput>] = []

        for skip in self.skipAlbumRe {
            do {
                let regex = try Regex(skip)
                skipRe.append(regex)
            } catch {
                print("Regular expression '\(skip)' is not valid: \(error)")
                throw ExitCode.failure
            }
        }

        // Make sure the output directory exists (or can be created)
        if !FileManager.default.fileExists(atPath: outputDir) {
            do {
                try FileManager.default.createDirectory(
                    atPath: outputDir, withIntermediateDirectories: true, attributes: nil
                )
            } catch {
                print("ERROR: Failed to create output directory \(outputDir): \(error)")
                throw ExitCode.failure
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

        let state = State(
            args: self,
            targetAspect: targetAspect,
            skipRe: skipRe,
            assetCheck: assetCheckFn
        )

        let success = await asyncMain(state: state)

        if !success {
            throw ExitCode.failure
        }
    }
}

struct State {
    var args: Args
    var targetAspect: Double
    var skipRe: [Regex<AnyRegexOutput>]
    var assetCheck: (PHAsset, State) -> Bool
}

/// Runs the tool. Returns false if a fatal error prevented processing from completing.
func asyncMain(state: State) async -> Bool {
    if state.args.verbose {
        print("Getting authorisation...")
    }

    guard await getAuth() else {
        return false
    }

    if state.args.verbose {
        print("Processing collections...")
    }

    await processTopLevelCollections(state: state)

    return true
}
