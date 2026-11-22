import SwiftUI
import StareCore

/// The first-run Setup Guide, redesigned after the chosen artboard
/// `design/setup-guide/03-permission-checklist.html` (T2/S1–S5, "03 ·
/// Permission checklist"): the single Screen Recording permission is one task
/// row inside a card, with its per-state action in the row, the app's own
/// icon above the title, and "Not now" demoted to the window's footer.
///
/// The window drives the model (`OnboardingWindowController` refreshes it on
/// appear, on activation and on a short timer); the view only renders the
/// state and calls back. The per-state action hierarchy — exactly one primary
/// action, at most one secondary — is not decided here at all: it comes from
/// `OnboardingActionPlan` in StareCore via `model.actionPlan`, so the three
/// states map to their actions exactly as the tests pin them.
///
/// Native, honest macOS look: system fonts, SF Symbols and `NSColor` semantic
/// colors — never the artboards' web tokens, which describe the landing page.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let onContinue: () -> Void
    let onRestart: () -> Void
    let onNotNow: () -> Void

    /// The guide's supporting copy: the header's one-liner, the card's status
    /// detail and the demoted "Not now". Kept as one named colour so the
    /// contrast it must meet is pinned in one place (spec S5, WCAG AA) instead
    /// of depending on whichever semantic colour each call site picked.
    ///
    /// Not `secondaryLabelColor`: that is a 50 % label in light mode, which
    /// measures 3.95:1 on the guide's backgrounds — short of the 4.5:1 AA asks
    /// for text this small (12–13 pt), even though it clears AA in dark mode.
    /// A 60 % label measures ~5.7:1 in light and ~6.7:1 in dark and still reads
    /// as secondary next to the 85 % label colour, so the hierarchy holds and
    /// AA holds with it. `OnboardingContrastTests` pins the ratio.
    ///
    /// Built as a dynamic colour on purpose: `labelColor.withAlphaComponent(_:)`
    /// settles on the appearance that happens to be current when it is created,
    /// which is how a "dimmer label" can end up white-on-white in light mode.
    static let supportingLabel = NSColor(name: nil) { appearance in
        var label = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            label = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
        }
        return label.withAlphaComponent(0.6)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            header
                .padding(.horizontal, 32)

            card
                .padding(.top, 18)
                .padding(.horizontal, 28)

            Spacer(minLength: 14)

            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            // The bundle's own icon file, not `NSApp.applicationIconImage`:
            // that one comes back desaturated on macOS 26, which is why the
            // guide used to show a gray placeholder instead of the aurora mark.
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)

            Text("Set up Stare")
                .font(.system(size: 22, weight: .bold))

            Text("One permission, once: Screen Recording.")
                .font(.callout)
                .foregroundStyle(Color(nsColor: Self.supportingLabel))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: The permission card

    /// The card the guide centers on: the one task row — mark, status copy from
    /// the model, and the per-state actions from `model.actionPlan`.
    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            task
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        // `contain`, never `combine`: the card holds the buttons, and a
        // combined subtree would collapse them into one accessibility element,
        // taking the primary action away from VoiceOver and full-keyboard
        // navigation.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen Recording permission: \(model.access.title)")
    }

    private var task: some View {
        HStack(alignment: .top, spacing: 14) {
            statusMark
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                // Status copy comes from the model — the view never invents
                // status strings.
                Text(model.access.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(model.access.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(nsColor: Self.supportingLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 8) {
                planActions
            }
        }
        .padding(.top, 6)
    }

    private var statusMark: some View {
        ZStack {
            Circle()
                .fill(markColor)
            Image(systemName: markSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    /// The actions `OnboardingActionPlan` decided for the current state:
    /// `primary` renders prominent (Return triggers it), the optional
    /// secondary renders bordered beside it. With the permission granted the
    /// plan contains no System Settings action at all, so none renders.
    @ViewBuilder
    private var planActions: some View {
        let plan = model.actionPlan

        Button(plan.primary.label) { perform(plan.primary.kind) }
            .buttonStyle(.borderedProminent)
            .tint(primaryTint)
            .keyboardShortcut(.defaultAction)
            .frame(minWidth: plan.primary.kind == .continueOnboarding ? 110 : 0)
            .accessibilityLabel(primaryAccessibilityLabel(plan.primary))

        if let secondary = plan.secondary {
            Button(secondary.label) { perform(secondary.kind) }
                .buttonStyle(.bordered)
                .accessibilityLabel(secondaryAccessibilityLabel(secondary))
        }
    }

    /// Maps each plan kind to its one existing path — the view owns no
    /// hierarchy rule, only this callback wiring.
    private func perform(_ kind: OnboardingAction.Kind) {
        switch kind {
        case .openSystemSettings:
            model.requestAccess()
            model.openSettings()
        case .restartStare:
            onRestart()
        case .continueOnboarding:
            onContinue()
        }
    }

    // MARK: Footer

    /// The bundle icon in full colour. `NSApp.applicationIconImage` returns a
    /// desaturated variant on macOS 26 and the guide rendered a gray square,
    /// so the real artwork is read from `Resources/AppIcon.icns` first.
    ///
    /// `let`, not `var`: the controller refreshes the model once a second, and a
    /// computed property would re-decode the 612 KB icon file on every tick.
    private static let appIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSApp.applicationIconImage
    }()

    private var footer: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)

            Button("Not now", action: onNotNow)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: Self.supportingLabel))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Not now — close the setup guide")
        }
    }

    // MARK: Per-state presentation

    private var markSymbol: String {
        switch model.access {
        case .denied: "minus"
        case .grantedPendingRestart: "arrow.triangle.2.circlepath"
        case .granted: "checkmark"
        }
    }

    private var markColor: Color {
        switch model.access {
        case .denied: Color(nsColor: .systemOrange)
        case .grantedPendingRestart: Color(nsColor: .systemOrange)
        case .granted: Color(nsColor: .systemGreen)
        }
    }

    /// The primary tint follows the state: accent for the two forward paths,
    /// the warning color while the only primary is the restart.
    private var primaryTint: Color {
        switch model.access {
        case .grantedPendingRestart: Color(nsColor: .systemOrange)
        case .denied, .granted: Color(nsColor: .controlAccentColor)
        }
    }

    private func primaryAccessibilityLabel(_ action: OnboardingAction) -> String {
        switch action.kind {
        case .openSystemSettings: "Open System Settings to allow Screen Recording and come back here"
        case .restartStare: "Restart Stare to finish granting Screen Recording"
        case .continueOnboarding: "Continue — Stare is ready to use"
        }
    }

    private func secondaryAccessibilityLabel(_ action: OnboardingAction) -> String {
        switch action.kind {
        case .openSystemSettings: "Re-authorize Stare in System Settings"
        case .restartStare: "Restart Stare"
        case .continueOnboarding: "Continue"
        }
    }
}
