import SwiftUI
import WidgetKit

@main
struct LingpaoWidgetBundle: WidgetBundle {
    var body: some Widget {
        InteractiveControlWidget()
        CompactVehicleWidget()
        LockScreenRangeWidget()
        ChargeLiveActivityWidget()
    }
}
