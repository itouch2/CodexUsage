import SwiftUI

struct WidgetStudioPreview: View {
    @ObservedObject var viewModel: AgentUsageViewModel
    @ObservedObject var controller: CodexUsageDesktopWidgetController
    @Environment(\.colorScheme) private var colorScheme

    private let widgetAspectRatio: CGFloat = 360.0 / 220.0
    private let designGradientTopColor = Color(
        red: 205.0 / 255.0,
        green: 219.0 / 255.0,
        blue: 236.0 / 255.0
    )
    private let designGradientMiddleColor = Color(
        red: 237.0 / 255.0,
        green: 231.0 / 255.0,
        blue: 225.0 / 255.0
    )
    private let designGradientBottomColor = Color(
        red: 248.0 / 255.0,
        green: 237.0 / 255.0,
        blue: 208.0 / 255.0
    )

    var body: some View {
        GeometryReader { geometry in
            let previewWidth = min(
                max(320, geometry.size.width - 88),
                max(320, (geometry.size.height - 132) * widgetAspectRatio),
                560
            )

            VStack(spacing: 18) {
                Spacer(minLength: 32)

                CodexUsageDesktopWidgetView(
                    viewModel: viewModel,
                    controller: controller
                )
                .frame(
                    width: previewWidth,
                    height: previewWidth / widgetAspectRatio
                )
                .allowsHitTesting(false)
                .shadow(color: .black.opacity(0.16), radius: 20, y: 12)
                .accessibilityLabel("Desktop widget preview")

                Text("Drag and resize directly on your desktop")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .opacity(0.68)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        designGradientTopColor.opacity(designGradientOpacity),
                        designGradientMiddleColor.opacity(designGradientOpacity),
                        designGradientBottomColor.opacity(designGradientOpacity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
    }

    private var designGradientOpacity: Double {
        colorScheme == .dark ? 0.24 : 1
    }
}
