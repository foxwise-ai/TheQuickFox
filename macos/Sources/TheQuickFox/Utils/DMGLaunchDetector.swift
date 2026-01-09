//
//  DMGLaunchDetector.swift
//  TheQuickFox
//
//  Detects if the application is being launched from a DMG (disk image)
//  and provides functionality to move it to the Applications folder.
//

import AppKit
import Foundation

enum DMGLaunchDetector {

    /// Result of the DMG launch check
    enum LaunchLocation {
        case applicationsFolder
        case dmgVolume(volumePath: String)
        case otherLocation(path: String)
    }

    /// Error types for move operation
    enum MoveError: Error, LocalizedError {
        case sourceNotFound
        case destinationExists
        case moveOperationFailed(underlying: Error)
        case permissionDenied
        case unknownError

        var errorDescription: String? {
            switch self {
            case .sourceNotFound:
                return "The application could not be found at its current location."
            case .destinationExists:
                return "TheQuickFox already exists in the Applications folder."
            case .moveOperationFailed(let underlying):
                return "Failed to move the application: \(underlying.localizedDescription)"
            case .permissionDenied:
                return "Permission denied. Please move the application manually."
            case .unknownError:
                return "An unknown error occurred while moving the application."
            }
        }
    }

    /// Checks where the application is being launched from
    static func checkLaunchLocation() -> LaunchLocation {
        let bundlePath = Bundle.main.bundlePath

        // Check if running from /Applications
        if bundlePath.hasPrefix("/Applications/") {
            return .applicationsFolder
        }

        // Check if running from user's Applications folder
        let userApplications = NSHomeDirectory() + "/Applications/"
        if bundlePath.hasPrefix(userApplications) {
            return .applicationsFolder
        }

        // Check if running from a mounted volume (likely a DMG)
        // DMG volumes are typically mounted at /Volumes/
        if bundlePath.hasPrefix("/Volumes/") {
            // Extract the volume name
            let components = bundlePath.components(separatedBy: "/")
            if components.count >= 3 {
                let volumePath = "/Volumes/\(components[2])"

                // Additional check: verify this is actually a disk image mount
                // by checking if it's a read-only volume or has typical DMG characteristics
                if isDMGVolume(path: volumePath) {
                    return .dmgVolume(volumePath: volumePath)
                }
            }
        }

        return .otherLocation(path: bundlePath)
    }

    /// Determines if the path is a mounted DMG volume
    private static func isDMGVolume(path: String) -> Bool {
        let fileManager = FileManager.default

        // Check if the volume is writable - DMGs are typically read-only
        // However, some DMGs can be writable, so we also check other indicators
        let isWritable = fileManager.isWritableFile(atPath: path)

        // Check for common DMG indicators:
        // 1. Contains a .app and a symlink to /Applications (common DMG layout)
        // 2. Is mounted as a disk image

        // Try to get volume info
        do {
            let resourceValues = try URL(fileURLWithPath: path).resourceValues(forKeys: [
                .volumeIsReadOnlyKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey
            ])

            // If it's ejectable or read-only, it's likely a DMG
            if resourceValues.volumeIsReadOnly == true ||
               resourceValues.volumeIsEjectable == true {
                return true
            }
        } catch {
            // If we can't get volume info, fall back to heuristics
        }

        // Heuristic: Check if there's a symlink to /Applications (common DMG layout)
        let applicationsLink = (path as NSString).appendingPathComponent("Applications")
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: applicationsLink, isDirectory: &isDirectory) {
            // Check if it's a symlink
            do {
                let attrs = try fileManager.attributesOfItem(atPath: applicationsLink)
                if let fileType = attrs[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
                    return true
                }
            } catch {
                // Ignore errors
            }
        }

        // Another heuristic: DMG volumes often aren't writable
        if !isWritable {
            return true
        }

        // If the bundle path contains the volume name and is at the root,
        // it's probably a DMG (e.g., /Volumes/TheQuickFox/TheQuickFox.app)
        let bundlePath = Bundle.main.bundlePath
        let volumeName = (path as NSString).lastPathComponent
        let expectedDMGPath = "\(path)/\(volumeName).app"
        let altExpectedPath = "\(path)/TheQuickFox.app"

        if bundlePath == expectedDMGPath || bundlePath == altExpectedPath {
            return true
        }

        return false
    }

    /// Returns true if the app is running from a DMG
    static var isRunningFromDMG: Bool {
        if case .dmgVolume = checkLaunchLocation() {
            return true
        }
        return false
    }

    /// Returns the path to the Applications folder
    static var applicationsPath: String {
        "/Applications"
    }

    /// Returns the destination path for the app in Applications
    static var destinationPath: String {
        let appName = (Bundle.main.bundlePath as NSString).lastPathComponent
        return (applicationsPath as NSString).appendingPathComponent(appName)
    }

    /// Checks if the app already exists in Applications folder
    static var existsInApplications: Bool {
        FileManager.default.fileExists(atPath: destinationPath)
    }

    /// Moves the application to the Applications folder
    /// - Parameter completion: Called with the result of the move operation
    static func moveToApplications(completion: @escaping (Swift.Result<Void, MoveError>) -> Void) {
        let fileManager = FileManager.default
        let sourcePath = Bundle.main.bundlePath
        let destPath = destinationPath

        // Verify source exists
        guard fileManager.fileExists(atPath: sourcePath) else {
            completion(.failure(.sourceNotFound))
            return
        }

        // Check if destination already exists
        if fileManager.fileExists(atPath: destPath) {
            // Try to remove the existing app first
            do {
                try fileManager.removeItem(atPath: destPath)
            } catch {
                // If we can't remove, try to trash it
                do {
                    try fileManager.trashItem(at: URL(fileURLWithPath: destPath), resultingItemURL: nil)
                } catch {
                    completion(.failure(.destinationExists))
                    return
                }
            }
        }

        // Perform the copy (not move, since source is read-only on DMG)
        do {
            try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
            completion(.success(()))
        } catch let error as NSError {
            if error.code == NSFileWriteNoPermissionError {
                completion(.failure(.permissionDenied))
            } else {
                completion(.failure(.moveOperationFailed(underlying: error)))
            }
        }
    }

    /// Launches the app from the Applications folder and quits the current instance
    static func launchFromApplicationsAndQuit() {
        let destPath = destinationPath

        // Use NSWorkspace to launch the app
        let url = URL(fileURLWithPath: destPath)

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error = error {
                print("❌ Failed to launch app from Applications: \(error)")
            }
        }

        // Quit this instance after a short delay to allow the new instance to start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}
