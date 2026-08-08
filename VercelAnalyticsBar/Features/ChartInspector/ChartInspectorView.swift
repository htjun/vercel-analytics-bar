#if CHART_INSPECTOR
    import SwiftUI

    enum ChartInspectorScene {
        static let id = "chart-inspector"
    }

    struct ChartInspectorView: View {
        let styleStore: ChartStyleStore

        var body: some View {
            ChartInspectorWebView(styleStore: styleStore)
                .frame(minWidth: 320, minHeight: 560)
        }
    }
#endif
