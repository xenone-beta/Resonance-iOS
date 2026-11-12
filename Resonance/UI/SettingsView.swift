import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var library: Library
    @Environment(\.palette) private var palette
    @State private var pickerOpen = false

    private var isCustom: Bool { !Settings.accentSeeds.contains(settings.accent) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.themeMode) {
                        ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Accent color")
                        swatches
                    }
                    .padding(.vertical, 6)
                    Toggle("Colors from the cover", isOn: $settings.coverColors)
                    Toggle("Gradient in the player", isOn: $settings.playerGradient)
                    Toggle("Spectrum ring", isOn: $settings.visualizer)
                    Toggle("Wavy progress bar", isOn: $settings.wavySeek)
                }

                Section("Language") {
                    Picker("Language", selection: $settings.language) {
                        Text("System").tag("")
                        ForEach(Settings.languages, id: \.tag) { Text($0.name).tag($0.tag) }
                    }
                }

                Section("Library") {
                    Button {
                        Task { await library.rescan() }
                    } label: {
                        HStack {
                            Text("Rescan library")
                            Spacer()
                            if library.isScanning { ProgressView() }
                        }
                    }
                    Text("Copy music into the Resonance folder in the Files app (On My iPhone), then pull down on Songs.")
                        .font(.footnote)
                        .foregroundStyle(palette.onSurfaceVariant)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Self.version).foregroundStyle(palette.onSurfaceVariant)
                    }
                    Link("GitHub", destination: URL(string: "https://github.com/xenone-beta/Resonance-iOS")!)
                }
            }
            .tint(palette.primary)
            .scrollContentBackground(.hidden)
            .background(palette.surface)
            .navigationTitle("Settings")
            .sheet(isPresented: $pickerOpen) {
                ColorPickerView(initial: settings.accent) { settings.accent = $0 }
                    .environment(\.palette, palette)
                    .presentationDetents([.large])
            }
        }
    }

    private var swatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button { pickerOpen = true } label: {
                    ZStack {
                        Circle().fill(isCustom ? Color(argb: settings.accent) : palette.surfaceContainerHigh)
                        Image(systemName: isCustom ? "checkmark" : "eyedropper")
                            .foregroundStyle(isCustom ? Color.white : palette.onSurfaceVariant)
                    }
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(palette.onSurface, lineWidth: isCustom ? 3 : 0))
                }
                .buttonStyle(.plain)
                ForEach(Settings.accentSeeds, id: \.self) { seed in
                    Button { settings.accent = seed } label: {
                        Circle().fill(Color(argb: seed))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "checkmark").foregroundStyle(.white)
                                    .opacity(settings.accent == seed ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
