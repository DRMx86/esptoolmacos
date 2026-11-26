import SwiftUI

// MARK: - Card

struct CardModifier: ViewModifier {
    let p: Palette

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(p.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.border, lineWidth: 1))
    }
}

extension View {
    func card(_ p: Palette) -> some View {
        modifier(CardModifier(p: p))
    }

    /// Minimal text field look used across the app.
    func themedField(_ p: Palette) -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(p.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.background))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.border, lineWidth: 1))
    }
}

// MARK: - Labels

struct SectionLabel: View {
    let text: String
    let p: Palette

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: p.fontDesign))
            .tracking(1.2)
            .foregroundColor(p.secondaryText)
    }
}

// MARK: - Buttons

struct ThemedButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }

    let p: Palette
    var kind: Kind = .secondary

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fg: Color
        let bg: Color
        let stroke: Color
        switch kind {
        case .primary:
            fg = p.onAccent; bg = p.accent; stroke = .clear
        case .secondary:
            fg = p.text; bg = .clear; stroke = p.border
        case .danger:
            fg = p.danger; bg = .clear; stroke = p.danger.opacity(0.6)
        }
        return configuration.label
            .font(.system(size: 13, weight: .semibold, design: p.fontDesign))
            .foregroundColor(fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(stroke, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1.0) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Menu picker

struct ThemedMenu<Value: Hashable>: View {
    let p: Palette
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { selection = option }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label(selection))
                    .font(.system(size: 13, design: p.fontDesign))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(p.secondaryText)
            }
            .foregroundColor(p.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.background))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Progress bar

struct ThemedProgressBar: View {
    let value: Double
    let p: Palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.border)
                Capsule()
                    .fill(p.accent)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .animation(.easeOut(duration: 0.15), value: value)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Status dot

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.7), radius: 3)
    }
}
