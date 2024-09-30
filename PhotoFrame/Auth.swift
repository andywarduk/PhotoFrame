//
//  Auth.swift
//  PhotoFrame
//
//  Created by Andrew Ward on 30/09/2024.
//

import Photos

/// Get authorisation to access the photos library
func getAuth() async -> Bool {
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
