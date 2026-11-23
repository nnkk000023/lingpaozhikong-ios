import ActivityKit
import LingpaoCore
import SwiftUI
import WidgetKit

/// 灵动岛与锁屏实时充电 Live Activity 视图（聚焦实时充电功率与预计剩余时间）
public struct ChargeLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargeActivityAttributes.self) { context in
            // 锁屏与横幅实时充电卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(context.attributes.vehicleName, systemImage: "bolt.car.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("充电进行中")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(Color(red: 0.12, green: 0.64, blue: 0.39))
                        .background(Capsule().fill(Color(red: 0.12, green: 0.64, blue: 0.39).opacity(0.16)))
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f kW", context.state.powerKw))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.12, green: 0.64, blue: 0.39))
                        Text("当前实时功率")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("约剩 \(max(context.state.remainMinutes, 0)) 分钟")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("电量 \(context.state.soc)% · 续航 \(context.state.rangeKm) km")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: Double(context.state.soc), total: 100.0)
                    .tint(Color(red: 0.12, green: 0.64, blue: 0.39))
            }
            .padding(16)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.92))
            .activitySystemActionForegroundColor(Color(red: 0.12, green: 0.64, blue: 0.39))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时功率")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f kW", context.state.powerKw))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.64, blue: 0.39))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("预计剩余")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(max(context.state.remainMinutes, 0)) 分钟")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: Double(context.state.soc), total: 100.0)
                            .tint(Color(red: 0.12, green: 0.64, blue: 0.39))
                        HStack {
                            Text("\(context.attributes.vehicleName) · \(context.state.soc)% (目标 \(context.state.targetSoc)%)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("续航 \(context.state.rangeKm) km")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.64, blue: 0.39))
                    Text(String(format: "%.1fkW", context.state.powerKw))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            } compactTrailing: {
                Text("剩\(max(context.state.remainMinutes, 0))分")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color(red: 0.12, green: 0.64, blue: 0.39))
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color(red: 0.12, green: 0.64, blue: 0.39))
            }
        }
    }
}
