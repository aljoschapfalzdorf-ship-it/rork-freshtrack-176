import SwiftUI

/// Monochrome design tokens. See .rork/DESIGN.md.
enum Theme {
    static let canvas = Color.black
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let surfaceHigh = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let primary = Color.white
    static let secondary = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let hairline = Color.white.opacity(0.10)
    static let destructive = Color(red: 1, green: 59 / 255, blue: 48 / 255)

    static let cardRadius: CGFloat = 26
    static let smallRadius: CGFloat = 14
}

/// Near-black canvas with a faint top glow so glass has something to refract.
struct AtmosphereBackground: View {
    var body: some View {
        ZStack {
            Theme.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.09), .clear],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 10,
                endRadius: 520
            )
            RadialGradient(
                colors: [Color.white.opacity(0.04), .clear],
                center: .init(x: 1.0, y: 0.85),
                startRadius: 10,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Liquid Glass on iOS 26, frosted material with a hairline highlight before that.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.10), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                }
                .overlay { shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5) }
        }
    }

    /// Solid elevated content surface (cards are content, not chrome).
    func contentCard(radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
            }
    }
}

/// Subtle scale-down press feedback for custom buttons.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round glass icon button (search, scan, close, flash ...).
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 58
    var iconSize: CGFloat = 22
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: size, height: size)
                .contentShape(.circle)
                .glassSurface(Circle(), interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}

/// Product photo that always respects its frame.
struct ProductImage: View {
    let category: ProductCategory

    var body: some View {
        Theme.surfaceHigh
            .overlay {
                Image(category.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .clipped()
    }
}
