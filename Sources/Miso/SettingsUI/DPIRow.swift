import MisoCore
import SwiftUI

struct DPIRow: View {
    @ObservedObject var model: SettingsModel
    let device: MouseDevice
    let showsName: Bool
    @State private var draft: Double?

    var body: some View {
        if let dpi = device.dpi {
            if dpi.values.isEmpty {
                slider(dpi)
            } else {
                Picker(title, selection: Binding(
                    get: { dpi.current },
                    set: { model.setDPI($0, for: device.id) }
                )) {
                    ForEach(dpi.values, id: \.self) { Text("\($0) DPI").tag($0) }
                }
            }
        } else {
            LabeledContent(title) {
                Text("Not adjustable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String { showsName ? device.name : "Resolution" }

    private func snap(_ value: Double, _ dpi: MouseDPI) -> Double {
        let step = Double(max(dpi.step, 1))
        return Double(dpi.minimum) + ((value - Double(dpi.minimum)) / step).rounded() * step
    }

    private func slider(_ dpi: MouseDPI) -> some View {
        let value = Int(draft ?? Double(dpi.current))
        return LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(get: { draft ?? Double(dpi.current) }, set: { draft = snap($0, dpi) }),
                    in: Double(dpi.minimum)...Double(max(dpi.maximum, dpi.minimum + 1))
                ) {
                    Text(title)
                } onEditingChanged: { editing in
                    // Only send the final value so the mouse is not flooded with HID writes.
                    guard !editing, let draft else { return }
                    model.setDPI(Int(draft), for: device.id)
                    self.draft = nil
                }
                .labelsHidden()
                .accessibilityValue("\(value) DPI")
                Text("\(value) DPI")
                    .monospacedDigit()
                    .frame(width: SettingsLayout.valueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
}
