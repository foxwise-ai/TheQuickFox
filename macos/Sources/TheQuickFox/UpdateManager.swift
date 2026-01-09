import Foundation
import Sparkle

/// Manages automatic updates using Sparkle framework
final class UpdateManager: NSObject {
    static let shared = UpdateManager()
    
    private var updaterController: SPUStandardUpdaterController?
    
    private func initializeUpdater() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        print("✅ Sparkle updater controller initialized")
    }
    
    override init() {
        super.init()
    }
    
    /// The Sparkle updater instance
    var updater: SPUUpdater? {
        return updaterController?.updater
    }
    
    /// Configure the updater with appcast URL and settings
    func configure() {
        // Initialize updater if needed
        if updaterController == nil {
            initializeUpdater()
        }
        
        guard let updater = updater else {
            print("❌ Updater not available")
            return
        }
        
        // Configure update check interval (in seconds)
        updater.updateCheckInterval = 60 * 60 * 24 // Check daily
        
        // Enable automatic checks by default
        updater.automaticallyChecksForUpdates = true
        
        // Enable automatic downloads
        updater.automaticallyDownloadsUpdates = false
        
        // For local testing, disable signature verification
        #if DEBUG
        if let feedURL = updater.feedURL, feedURL.host == "localhost" {
            print("⚠️ Local testing mode - signature verification may fail")
        }
        #endif
        
        // Log current settings
        print("✅ Sparkle updater configured:")
        print("   - Feed URL: \(updater.feedURL?.absoluteString ?? "not set")")
        print("   - Auto-check: \(updater.automaticallyChecksForUpdates)")
        print("   - Auto-download: \(updater.automaticallyDownloadsUpdates)")
        print("   - Check interval: \(updater.updateCheckInterval / 3600) hours")
    }
    
    /// Manually check for updates
    func checkForUpdates() {
        if updaterController == nil {
            initializeUpdater()
        }
        updater?.checkForUpdates()
    }
    
    /// Check for updates in background (no UI if no update)
    func checkForUpdatesInBackground() {
        if updaterController == nil {
            initializeUpdater()
        }
        updater?.checkForUpdatesInBackground()
    }
}

// MARK: - SPUUpdaterDelegate
extension UpdateManager: SPUUpdaterDelegate {
    /// Modify the appcast request to add authentication headers
    func updater(_ updater: SPUUpdater, httpHeaders httpHeaders: [String : String]) -> [String : String] {
        var headers = httpHeaders
        
        // Try to get auth token from keychain
        if let authToken = try? KeychainManager.shared.getAuthToken() {
            headers["Authorization"] = "Bearer \(authToken)"
            print("✅ Added auth header to Sparkle appcast request")
        } else {
            print("ℹ️ No auth token available for Sparkle appcast request - will get public stable version")
        }
        
        return headers
    }
}