import SwiftUI

struct AnimatedBackgroundView: View {
    @Binding var touchLocation: CGPoint?

    @State private var orb1Phase = false
    @State private var orb2Phase = false
    @State private var orb3Phase = false
    @State private var orb4Phase = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                // Base
                Color.white

                // Floating orbs
                orb(
                    size: 600,
                    baseX: size.width * 0.8,
                    baseY: -size.height * 0.2,
                    phase: orb1Phase,
                    xRange: 40,
                    yRange: 30,
                    opacity: 0.08
                )

                orb(
                    size: 500,
                    baseX: -size.width * 0.2,
                    baseY: size.height * 1.1,
                    phase: orb2Phase,
                    xRange: 35,
                    yRange: 25,
                    opacity: 0.05
                )

                orb(
                    size: 400,
                    baseX: size.width * 1.05,
                    baseY: size.height * 0.4,
                    phase: orb3Phase,
                    xRange: 30,
                    yRange: 35,
                    opacity: 0.06
                )

                orb(
                    size: 300,
                    baseX: size.width * 0.5,
                    baseY: size.height * 1.1,
                    phase: orb4Phase,
                    xRange: 25,
                    yRange: 20,
                    opacity: 0.04
                )

                // Subtle grid overlay
                GridOverlay()

                // Touch-follow glow
                if let point = touchLocation {
                    Circle()
                        .fill(Theme.accent.opacity(0.03))
                        .frame(width: 600, height: 600)
                        .blur(radius: 80)
                        .position(point)
                        .animation(.easeOut(duration: 1.0), value: point)
                }
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 8)
                    .repeatForever(autoreverses: true)
                ) {
                    orb1Phase.toggle()
                }
                withAnimation(
                    .easeInOut(duration: 8)
                    .delay(2)
                    .repeatForever(autoreverses: true)
                ) {
                    orb2Phase.toggle()
                }
                withAnimation(
                    .easeInOut(duration: 8)
                    .delay(4)
                    .repeatForever(autoreverses: true)
                ) {
                    orb3Phase.toggle()
                }
                withAnimation(
                    .easeInOut(duration: 8)
                    .delay(1)
                    .repeatForever(autoreverses: true)
                ) {
                    orb4Phase.toggle()
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Orb

    @ViewBuilder
    private func orb(
        size: CGFloat,
        baseX: CGFloat,
        baseY: CGFloat,
        phase: Bool,
        xRange: CGFloat,
        yRange: CGFloat,
        opacity: Double
    ) -> some View {
        Circle()
            .fill(Theme.accent.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: 80)
            .scaleEffect(phase ? 1.05 : 0.95)
            .offset(
                x: baseX + (phase ? xRange : -xRange),
                y: baseY + (phase ? yRange : -yRange)
            )
    }
}

// MARK: - Grid Overlay

private struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 64
            var path = Path()

            // Vertical lines
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            // Horizontal lines
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(
                path,
                with: .color(Color.black.opacity(0.08)),
                lineWidth: 0.5
            )
        }
        .blendMode(.normal)
        .allowsHitTesting(false)
    }
}

