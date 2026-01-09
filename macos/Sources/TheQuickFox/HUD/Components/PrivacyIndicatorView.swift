//
//  PrivacyIndicatorView.swift
//  TheQuickFox
//
//  Shows captured screenshot thumbnail with click-to-preview
//

import SwiftUI
import AppKit

struct PrivacyIndicatorView: View {
    let screenshot: NSImage?
    let appIcon: NSImage?
    @State private var isShowingPreview = false

    var body: some View {
        if let screenshot = screenshot {
            Button(action: { isShowingPreview = true }) {
                HStack(spacing: 6) {
                    // App icon
                    if let icon = appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    }

                    Text("Screenshot captured")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))

                    Image(systemName: "eye")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPreview) {
                ScreenshotPreviewView(screenshot: screenshot)
            }
        } else {
            // No screenshot yet - show nothing or minimal indicator
            EmptyView()
        }
    }
}

struct ScreenshotPreviewView: View {
    let screenshot: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured Screenshot")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Image(nsImage: screenshot)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 400, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("We don't save this. Once you get your answer, it's gone.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(12)
    }
}

#Preview {
    VStack(spacing: 20) {
        // With screenshot and icon
        PrivacyIndicatorView(
            screenshot: NSImage(named: NSImage.computerName),
            appIcon: NSImage(named: NSImage.applicationIconName)
        )

        // Without screenshot
        PrivacyIndicatorView(screenshot: nil, appIcon: nil)
    }
    .padding()
    .background(Color.black)
}
