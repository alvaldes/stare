import SwiftUI
import StareCore

/// Every preference Stare has, bound straight to the object that owns them.
struct SettingsView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        Form {
            Section("Drawing") {
                Toggle("Show drawing frame", isOn: $state.showArmedFrame)
                Text("A thin frame in the active ink marks every display that will take a mark.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Displays") {
                Picker("Draw on", selection: $state.overlayScope) {
                    Text("Every display").tag("all")
                    Text("Only the active display").tag("active")
                }
                Picker("Open the palette", selection: $state.palettePlacement) {
                    Text("Under the pointer").tag("cursor")
                    Text("On the display of the front window").tag("frontWindow")
                    Text("On the last used display").tag("fixed")
                }
                Text("Marking every display is the default; the palette follows the pointer unless told otherwise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Laser") {
                Picker("Laser lasts", selection: $state.laserLifetime) {
                    // 2.5 is the stored default: leaving it out showed an empty picker.
                    ForEach([1.0, 2.0, 2.5, 3.0, 5.0], id: \.self) { seconds in
                        Text(seconds == seconds.rounded() ? "\(Int(seconds)) seconds" : "\(seconds, specifier: "%g") seconds")
                            .tag(seconds)
                    }
                }
                Text("Laser marks fade out and never appear in a capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pointer highlight") {
                Picker("Size", selection: $state.pointerSize) {
                    ForEach([32.0, 44.0, 60.0, 72.0, 80.0], id: \.self) { size in
                        Text("\(Int(size)) pt").tag(CGFloat(size))
                    }
                }
                Picker("Shape", selection: $state.pointerShape) {
                    Text("Circle").tag("circle")
                    Text("Squircle").tag("squircle")
                }
                Toggle("Glow", isOn: $state.pointerGlow)
                Toggle("Fade when idle", isOn: $state.pointerFadeWhenIdle)
                Text("The highlight follows the pointer in presentation mode (⌥⇧M) and never takes focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
