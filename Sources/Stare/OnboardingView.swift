import SwiftUI
import StareCore

/// The first-run guide (T5/S1–S2): what Stare does, why it needs Screen
/// Recording, the current permission state, and the two ways forward — grant
/// it in System Settings and continue, or step aside with "Not now".
///
/// The window drives the model (`OnboardingWindowController` refreshes it on
/// appear, on activation and on a short timer); the view only renders the
/// state and calls back.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let onContinue: () -> Void
    let onRestart: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .padding(.top, 28)

            Text("Stare")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 14)

            Text(
                "Stare draws over your screen and captures it with your marks. " +
                    "It needs Screen Recording to see what you draw over."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32)
            .padding(.top, 8)

            permissionRow
                .padding(.top, 20)
                .padding(.horizontal, 28)

            VStack(spacing: 10) {
                Button {
                    model.requestAccess()
                    model.openSettings()
                } label: {
                    Text("Open System Settings…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.access == .granted)

                HStack(spacing: 10) {
                    Button("Continue", action: onContinue)
                        .buttonStyle(.bordered)
                        .disabled(!model.access.isGranted)

                    if model.access == .grantedPendingRestart {
                        Button("Restart Stare", action: onRestart)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                }

                Button("Not now", action: onNotNow)
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.horizontal, 32)

            Spacer(minLength: 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The one permission Stare needs, with the state copy from
    /// `ScreenRecordingAccess`: granted, needed, or granted but restart
    /// required.
    private var permissionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 22))
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.access.title)
                    .font(.headline)
                Text(model.access.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private var statusSymbol: String {
        switch model.access {
        case .denied: "lock.shield"
        case .granted: "checkmark.circle.fill"
        case .grantedPendingRestart: "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch model.access {
        case .denied: .orange
        case .granted: .green
        case .grantedPendingRestart: .orange
        }
    }
}
