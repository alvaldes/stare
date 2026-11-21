import SwiftUI
import StareCore

// The SwiftUI primitives the Settings sidebar and panes are built from. Kept
// deliberately small: no theme system, no design tokens — just the card, row and
// header shapes every pane shares, styled with the app's existing materials.

/// A titled card with a divider and the content stacked beneath: the one
/// container a pane uses, with the same `.ultraThinMaterial` and rounded
/// corners as the toolbar's cards.
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )
                Text(title)
                    .font(.headline)
            }
            Divider()
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}

/// One setting: title and optional detail on the left, the control on the
/// right, on a single line.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    let content: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            content
        }
    }
}

/// The title every pane opens with.
struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small status dot colouring the Screen Recording permission state: green
/// when capturing works, amber when a decision is still pending.
struct StatusDot: View {
    let state: ScreenRecordingAccess

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
    }

    private var color: Color {
        switch state {
        case .granted: .green
        case .denied, .grantedPendingRestart: .orange
        }
    }
}

/// The app icon, at the size the caller wants (the About pane shows it at 56
/// points).
struct AppMark: View {
    var size: CGFloat = 36

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// App version from the bundle, with the dev-runner fallback: `swift run` has
/// no Info.plist, and "0.2.0" is the version the changelog continues.
enum AppVersion {
    static let short = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0.2.0"
}
