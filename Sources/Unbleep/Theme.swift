import SwiftUI

/// Colors pulled from the app icon: a night-indigo field, a muffled tape gray for clean edits,
/// and the signal cyan of the uncensored word.
extension Color {
    static let night = Color(red: 0x12 / 255, green: 0x11 / 255, blue: 0x3A / 255)
    static let panel = Color(red: 0x1C / 255, green: 0x1A / 255, blue: 0x4D / 255)
    static let tape = Color(red: 0x8C / 255, green: 0x88 / 255, blue: 0xAE / 255)
    static let signal = Color(red: 0x3D / 255, green: 0xD8 / 255, blue: 0xFF / 255)
    static let hairline = Color.white.opacity(0.09)
}

extension Font {
    /// The heavy, compressed face used for song titles and headlines.
    static func poster(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.compressed)
    }
}

/// A strip of torn gaffer tape. Its ragged ends are seeded so a strip keeps its shape between renders.
struct CensorTape: View {
    var seed = 7

    var body: some View {
        TapeShape(seed: seed)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.30), Color(white: 0.20), Color(white: 0.26)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay {
                TapeShape(seed: seed)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}

private struct TapeShape: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        let teeth = max(4, Int(rect.height / 4))
        let step = rect.height / CGFloat(teeth)
        let jag = { (index: Int, side: Int) -> CGFloat in
            let value = (index * 37 + side * 53 + seed * 11) % 7
            return CGFloat(value) / 7 * min(6, rect.width * 0.05)
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + jag(0, 0), y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - jag(0, 1), y: rect.minY))
        for index in 1...teeth {
            path.addLine(to: CGPoint(x: rect.maxX - jag(index, 1), y: rect.minY + step * CGFloat(index)))
        }
        path.addLine(to: CGPoint(x: rect.minX + jag(teeth, 0), y: rect.maxY))
        for index in stride(from: teeth - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(x: rect.minX + jag(index, 0), y: rect.minY + step * CGFloat(index)))
        }
        path.closeSubpath()
        return path
    }
}

/// The little rounded "E" Apple Music uses, lit in signal cyan.
struct ExplicitBadge: View {
    var size: CGFloat = 16

    var body: some View {
        Text("E")
            .font(.system(size: size * 0.68, weight: .heavy))
            .foregroundStyle(Color.night)
            .frame(width: size, height: size)
            .background(Color.signal, in: .rect(cornerRadius: size * 0.22))
            .accessibilityLabel("Explicit")
    }
}

/// A keycap hint shown beside the action it triggers.
struct KeyHint: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, key.count > 1 ? 4 : 0)
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.2)) }
            .accessibilityHidden(true)
    }
}

/// The primary action: a solid cyan capsule with dark text.
struct SignalButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.night)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(Color.signal.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A quiet secondary action: text on a faint capsule.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(isEnabled ? 0.85 : 0.35))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.07), in: Capsule())
    }
}

extension ButtonStyle where Self == SignalButtonStyle {
    static var signal: SignalButtonStyle { SignalButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}
