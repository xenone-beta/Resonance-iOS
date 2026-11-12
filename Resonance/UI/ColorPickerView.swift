import SwiftUI

/// Builds any accent color: a saturation/brightness pad, a hue bar and a HEX field kept in sync.
struct ColorPickerView: View {
    let initial: UInt32
    let onPick: (UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var hue: Double = 0
    @State private var sat: Double = 0
    @State private var val: Double = 0
    @State private var hex = ""
    @State private var ready = false

    private var color: UIColor { UIColor(hue: hue, saturation: sat, brightness: val, alpha: 1) }
    private var parsed: UInt32? { Self.parse(hex) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                SVPad(hue: hue, sat: sat, val: val) { s, v in
                    sat = s; val = v; hex = Self.hexString(color)
                }
                .frame(height: 240)

                HueBar(hue: hue) { h in
                    hue = h; hex = Self.hexString(color)
                }
                .frame(height: 32)

                HStack(spacing: 16) {
                    Circle().fill(Color(color)).frame(width: 56, height: 56)
                    HStack(spacing: 4) {
                        Text("#").foregroundStyle(palette.onSurfaceVariant)
                        TextField("HEX", text: $hex)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .onChange(of: hex) { text in hexEdited(text) }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(parsed == nil ? Color.red : palette.primary, lineWidth: 2)
                    )
                }
                Spacer()
            }
            .padding(20)
            .background(palette.surface)
            .navigationTitle("Custom color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let argb = parsed { onPick(argb) }
                        dismiss()
                    }
                    .disabled(parsed == nil)
                }
            }
        }
        .onAppear {
            guard !ready else { return }
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(Color(argb: initial)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            hue = Double(h); sat = Double(s); val = Double(b)
            hex = Self.hexString(color)
            ready = true
        }
    }

    private func hexEdited(_ text: String) {
        let cleaned = String(text.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(6))
        if cleaned != text { hex = cleaned; return }
        guard let argb = Self.parse(cleaned) else { return }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(argb: argb)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h); sat = Double(s); val = Double(b)
    }

    static func parse(_ text: String) -> UInt32? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard t.count == 6, let value = UInt32(t, radix: 16) else { return nil }
        return 0xFF00_0000 | value
    }

    static func hexString(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

private struct SVPad: View {
    let hue: Double
    let sat: Double
    let val: Double
    let onChange: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .background(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1).padding(-2))
                    .frame(width: 24, height: 24)
                    .offset(x: sat * geo.size.width - 12, y: (1 - val) * geo.size.height - 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let s = min(max(value.location.x / geo.size.width, 0), 1)
                    let v = 1 - min(max(value.location.y / geo.size.height, 0), 1)
                    onChange(Double(s), Double(v))
                }
            )
        }
    }
}

private struct HueBar: View {
    let hue: Double
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6.0).map { Color(hue: $0, saturation: 1, brightness: 1) },
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(Capsule())
                Capsule()
                    .fill(Color.white)
                    .frame(width: 6, height: geo.size.height - 4)
                    .shadow(radius: 2)
                    .offset(x: min(max(hue * geo.size.width - 3, 0), geo.size.width - 6))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    onChange(Double(min(max(value.location.x / geo.size.width, 0), 1)))
                }
            )
        }
    }
}
