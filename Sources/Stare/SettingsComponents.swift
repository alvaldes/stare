import SwiftUI
import StareCore

// The SwiftUI primitives the Settings sidebar and panes are built from. Kept
// deliberately small: no theme system, no design tokens — just the card, row,
// pane and stage shapes every pane shares, styled with the app's existing
// materials.

/// The measurements the settings shell and its panes share, so the sidebar,
/// the pane padding and the column break stay one decision instead of three.
enum SettingsMetrics {
    /// The sidebar's fixed width; the pane area takes everything else.
    static let sidebarWidth: CGFloat = 190
    /// The pane area's horizontal padding, per side.
    static let panePadding: CGFloat = 22
    /// Below this card width a pane shows one column instead of two: a
    /// three-way segmented control and its label stop fitting side by side.
    static let twoColumnMinimum: CGFloat = 660
    /// Cards never grow past this in a single-column pane, so a row's label
    /// and its control stay within one glance on a wide window.
    static let singleColumnMaximum: CGFloat = 700
    /// Between two cards, and between the cards and the stage.
    static let cardSpacing: CGFloat = 14
}

/// A pane that is its own scroll container: the header stays put and the cards
/// move under it. Every pane except the ones with a stage uses this, and the
/// selftest renders a pane whole because the pane owns its scrolling.
struct SettingsPane<Cards: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let cards: Cards

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, SettingsMetrics.panePadding)
                .padding(.top, 18)
                .padding(.bottom, 14)

            ScrollView {
                cards
                    .toggleStyle(.switch)
                    .padding(.horizontal, SettingsMetrics.panePadding)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A pane with a live stage: the header and the stage never scroll, so what
/// the user is changing stays in view while the cards below move. This is the
/// shape the previews take — never a card at the end of a long pane.
struct StageSettingsPane<Stage: View, Cards: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let stage: Stage
    @ViewBuilder let cards: Cards

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, SettingsMetrics.panePadding)
                .padding(.top, 18)
                .padding(.bottom, 12)

            stage
                .padding(.horizontal, SettingsMetrics.panePadding)
                .padding(.bottom, 16)

            ScrollView {
                cards
                    .toggleStyle(.switch)
                    .padding(.horizontal, SettingsMetrics.panePadding)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The pinned region a preview lives in: a label that says what the stage is
/// showing, and the live view itself. The lead column keeps the stage's
/// explanation out of the way instead of pushing the preview down.
struct SettingsStage<Content: View>: View {
    let label: String
    let note: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 140, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8))
        )
    }
}

/// One or two columns of cards. Two columns use the width a wide window already
/// has instead of stretching every row across it; a narrow window folds back to
/// one column, in the order the pane reads when it is collapsed.
struct SettingsColumns<Left: View, Right: View>: View {
    let width: CGFloat
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        if width >= SettingsMetrics.twoColumnMinimum {
            HStack(alignment: .top, spacing: SettingsMetrics.cardSpacing) {
                VStack(spacing: SettingsMetrics.cardSpacing) { left }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: SettingsMetrics.cardSpacing) { right }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: SettingsMetrics.cardSpacing) {
                left
                right
            }
            .settingsSingleColumn()
        }
    }
}

extension View {
    /// Caps a pane's cards so a wide window does not stretch every row into a
    /// label on the far left and its control on the far right.
    func settingsSingleColumn() -> some View {
        frame(maxWidth: SettingsMetrics.singleColumnMaximum, alignment: .topLeading)
    }
}

/// A titled card with a divider and the content stacked beneath: the one
/// container a pane uses, with the same `.ultraThinMaterial` and rounded
/// corners as the toolbar's cards.
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            Divider()
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
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
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
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
