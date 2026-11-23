import MisoCore
import SwiftUI

/// Press-to-map: listens for the next mouse button and hands it to `capture`,
/// which returns an optional inline note (for example, "already mapped").
struct ButtonCaptureRow: View {
    @ObservedObject var model: SettingsModel
    let capture: (MouseButton) -> String?
    @State private var feedback: String?

    var body: some View {
        LabeledContent {
            Button {
                feedback = nil
                model.beginButtonRecording()
            } label: {
                Label("Press Button to Map…", systemImage: "computermouse")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!permitted)
        } label: {
            Text("Mappings")
            Text("Click, then press a middle, back, forward, extra or supported Logitech button.")
        }
        .sheet(isPresented: Binding(
            get: { model.isRecordingButton },
            set: { if !$0 { model.cancelButtonRecording() } }
        )) {
            ButtonRecordingSheet(cancel: model.cancelButtonRecording)
        }
        .onChange(of: model.recordedButton) { _, button in
            if let button { feedback = capture(button) }
        }
        if !permitted {
            PermissionNote(model: model)
        } else if let issue = model.logitechIssue {
            Label(issue, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        if let feedback {
            Label(feedback, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var permitted: Bool { model.accessibilityAllowed && model.inputMonitoringAllowed }
}

/// Shown instead of silently ignoring the capture button when access is missing.
private struct PermissionNote: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack {
            Label("Button capture needs \(missing) access.", systemImage: "lock.fill")
                .foregroundStyle(.orange)
            Spacer()
            Button("Grant Access…") {
                if !model.accessibilityAllowed { model.requestAccessibility() }
                if !model.inputMonitoringAllowed { model.requestInputMonitoring() }
            }
            Button("Check Again", action: model.refreshPermissions)
                .buttonStyle(.link)
        }
    }

    private var missing: String {
        switch (model.accessibilityAllowed, model.inputMonitoringAllowed) {
        case (false, false): "Accessibility and Input Monitoring"
        case (false, _): "Accessibility"
        default: "Input Monitoring"
        }
    }
}

private struct ButtonRecordingSheet: View {
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "computermouse")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
            Text("Press the Button to Map")
                .font(.headline)
            Text("Left and right clicks stay unchanged. Press Esc or Cancel to stop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 300)
    }
}
