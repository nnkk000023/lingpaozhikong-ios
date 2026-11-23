import AppIntents
import LingpaoCore
import SwiftUI
import WidgetKit

/// App Group 共享快照 Timeline Entry
public struct VehicleWidgetEntry: TimelineEntry {
    public let date: Date
    public let snapshot: SharedVehicleSnapshot

    public static var placeholder: VehicleWidgetEntry {
        VehicleWidgetEntry(
            date: Date(),
            snapshot: SharedVehicleSnapshot(
                vin: "DEMO",
                vehicleName: "零跑 C16",
                carType: "C16",
                paintId: "tianmu_gray",
                soc: 78,
                rangeKm: 162,
                isLocked: true,
                acOn: false,
                interiorTemp: 23.5,
                isCharging: false,
                chargePowerKw: 0,
                chargeRemainMinutes: 0
            )
        )
    }
}

public struct VehicleTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> VehicleWidgetEntry {
        .placeholder
    }

    public func getSnapshot(in context: Context, completion: @escaping (VehicleWidgetEntry) -> Void) {
        let snap = SharedSnapshotStore.load() ?? VehicleWidgetEntry.placeholder.snapshot
        completion(VehicleWidgetEntry(date: Date(), snapshot: snap))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<VehicleWidgetEntry>) -> Void) {
        let snap = SharedSnapshotStore.load() ?? VehicleWidgetEntry.placeholder.snapshot
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [VehicleWidgetEntry(date: Date(), snapshot: snap)], policy: .after(nextRefresh)))
    }
}

/// 1. 紧凑 2×2 车况展示 + 一键交互小组件
public struct CompactVehicleWidget: Widget {
    public let kind = "CompactVehicleWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VehicleTimelineProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.snapshot.carType)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: entry.snapshot.isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(entry.snapshot.isLocked ? Color(red: 0.12, green: 0.64, blue: 0.39) : .orange)
                }

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(entry.snapshot.soc.rounded()))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("续航 \(Int(entry.snapshot.rangeKm.rounded())) km")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(red: 0.12, green: 0.64, blue: 0.39))

                HStack(spacing: 6) {
                    if entry.snapshot.isLocked {
                        Button(intent: UnlockVehicleIntent()) {
                            Image(systemName: "lock.open.fill")
                                .font(.caption2.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 26)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.12, green: 0.64, blue: 0.39))
                    } else {
                        Button(intent: LockVehicleIntent()) {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 26)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.12, green: 0.64, blue: 0.39))
                    }

                    Button(intent: RefreshTelemetryIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(2)
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        }
        .configurationDisplayName("零跑紧凑车况")
        .description("展示实时电量、纯电续航，并支持一键解锁/闭锁")
        .supportedFamilies([.systemSmall])
    }
}

/// 2. 4×2 交互式桌面控车面板小组件（iOS 17 Interactive Widget）
public struct InteractiveControlWidget: Widget {
    public let kind = "InteractiveControlWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VehicleTimelineProvider()) { entry in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.snapshot.vehicleName)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        Text(entry.snapshot.lastActionMessage ?? (entry.snapshot.isLocked ? "全车已上锁" : "车门未锁定"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(entry.snapshot.soc.rounded()))%")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.64, blue: 0.39))
                        Text("\(Int(entry.snapshot.rangeKm.rounded())) km")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: min(max(entry.snapshot.soc / 100.0, 0), 1))
                    .tint(Color(red: 0.12, green: 0.64, blue: 0.39))

                HStack(spacing: 8) {
                    widgetActionButton(intent: UnlockVehicleIntent(), title: "解锁", icon: "lock.open.fill")
                    widgetActionButton(intent: LockVehicleIntent(), title: "锁车", icon: "lock.fill")
                    widgetActionButton(intent: ToggleClimateIntent(), title: entry.snapshot.acOn ? "关空调" : "开空调", icon: "fan.fill")
                    widgetActionButton(intent: FindCarIntent(), title: "寻车", icon: "horn.blast.fill")
                }
            }
            .padding(2)
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        }
        .configurationDisplayName("零跑桌面控车中心")
        .description("免打开 App，直接在桌面解锁、锁车、开关空调与鸣笛寻车")
        .supportedFamilies([.systemMedium])
    }

    @ViewBuilder
    private func widgetActionButton<I: AppIntent>(intent: I, title: String, icon: String) -> some View {
        Button(intent: intent) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.bordered)
        .tint(Color(red: 0.12, green: 0.64, blue: 0.39))
    }
}

/// 3. 锁屏电量/续航圆形微件
public struct LockScreenRangeWidget: Widget {
    public let kind = "LockScreenRangeWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VehicleTimelineProvider()) { entry in
            Gauge(value: min(max(entry.snapshot.soc, 0), 100), in: 0...100) {
                Text("电量")
            } currentValueLabel: {
                Text("\(Int(entry.snapshot.soc.rounded()))%")
                    .font(.caption2.weight(.bold))
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(for: .widget) {
                Color.clear
            }
        }
        .configurationDisplayName("零跑锁屏电量环")
        .description("在锁屏界面快速查看剩余电量")
        .supportedFamilies([.accessoryCircular])
    }
}
