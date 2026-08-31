import SwiftUI

struct AgentUsageView: View {
    @ObservedObject var viewModel: AgentUsageViewModel
    @ObservedObject private var widgetController =
        CodexUsageDesktopWidgetController.shared
    @ObservedObject private var locationRecorder =
        CodexLocationRecorder.shared

    var body: some View {
        HStack(spacing: 0) {
            WidgetStudioPreview(
                viewModel: viewModel,
                controller: widgetController
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            WidgetInspectorView(
                viewModel: viewModel,
                controller: widgetController,
                locationRecorder: locationRecorder
            )
            .frame(width: 310)
        }
    }
}
