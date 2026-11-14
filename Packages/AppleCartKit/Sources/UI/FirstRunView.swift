import Core
import SwiftUI

struct ReadoutPicker: View {
    @Bindable var readout: ReadoutSettings
    var body: some View {
        Picker("Next to the battery icon", selection: $readout.readout) {
            ForEach(MenuBarReadout.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.radioGroup)
        Text("Shows only while the Battery tool is on.").font(.callout).foregroundStyle(.secondary)
    }
}

/// Two screens, skippable from either with one click.
struct FirstRunView: View {
    let model: FirstRunModel
    @Bindable var readout: ReadoutSettings
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            if model.step == 0 {
                Image(systemName: "square.grid.2x2").font(.system(size: 34)).foregroundStyle(Palette.accent)
                Text("Pick only the tools you want").font(.title2.bold())
                Text("Everything starts off. A tool that is off uses no energy and asks for no permissions. Turn tools on any time in Settings.")
                    .foregroundStyle(Palette.secondary)
                Button("Choose tools") { openSettings() }
            } else {
                Image(systemName: "battery.75percent").font(.system(size: 34)).foregroundStyle(Palette.accent)
                Text("What to show in the menu bar").font(.title2.bold())
                ReadoutPicker(readout: readout)
            }
            Spacer()
            HStack {
                Button("Skip") { model.finish() }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
                Spacer()
                Text("\(model.step + 1) of \(FirstRunModel.stepCount)").font(.callout).foregroundStyle(Palette.secondary)
                Button(model.step + 1 >= FirstRunModel.stepCount ? "Done" : "Next") { model.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
