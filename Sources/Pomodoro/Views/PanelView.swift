import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var engine: TimerEngine

    var body: some View {
        let readout = engine.readout

        VStack(alignment: .leading, spacing: 14) {
            readoutBlock(readout)

            ProgressBarView(config: engine.config, progress: readout.progress)

            Divider()

            VStack(spacing: 8) {
                ForEach(Phase.allCases) { phase in
                    FieldRow(
                        color: phase.color,
                        symbol: phase.symbol,
                        title: phase.title,
                        unit: "min",
                        range: Limits.minutes,
                        value: engine.binding(for: Config.keyPath(for: phase))
                    )
                }
                Divider().padding(.vertical, 2)
                FieldRow(
                    color: .secondary,
                    symbol: SymbolName.rounds,
                    title: "Rounds",
                    unit: nil,
                    range: Limits.rounds,
                    value: engine.binding(for: \.rounds)
                )
            }
            .disabled(!readout.fieldsEnabled)
            .opacity(readout.fieldsEnabled ? 1 : 0.45)

            actions(readout)

            Divider()

            HStack {
                Text("Pomodoro").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func readoutBlock(_ readout: Readout) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(readout.clock)
                .font(.system(size: 40, weight: .thin, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 6) {
                Circle()
                    .fill(readout.isComplete ? Color.secondary : readout.phase.color)
                    .frame(width: 7, height: 7)
                Text(readout.phaseTitle.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                Spacer()
                Text("Round \(readout.round) of \(readout.rounds)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actions(_ readout: Readout) -> some View {
        HStack(spacing: 8) {
            Button(readout.isPaused ? "Resume" : "Start") { engine.start() }
                .disabled(readout.isRunning)
            Button("Pause") { engine.pause() }
                .disabled(!readout.isRunning)
            Button("Reset") { engine.reset() }
                .disabled(readout.isIdle)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }
}

private struct FieldRow: View {
    let color: Color
    /// The same glyph the menu bar shows for this phase, so the row doubles as
    /// the legend for what is up there.
    let symbol: String
    let title: String
    let unit: String?
    let range: ClosedRange<Int>
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            // A fixed slot, so glyphs of different widths still leave the
            // labels on one column.
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 4)
            if let unit {
                Text(unit).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 48)
                .labelsHidden()
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}
