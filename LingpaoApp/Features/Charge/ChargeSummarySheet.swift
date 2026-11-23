import Charts
import LingpaoCore
import SwiftUI

/// 充电完成或手动停止后弹出的总结与实时功率曲线报告弹窗（对齐全局设计语言与动画节奏）
public struct ChargeSummarySheet: View {
    public let summary: ChargeSessionSummary
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var chartRevealProgress: CGFloat = 0.0
    @State private var cardsVisible: Bool = false
    @State private var selectedElapsed: Double?

    public init(summary: ChargeSessionSummary) {
        self.summary = summary
    }

    private var selectedPoint: ChargeCurvePoint? {
        guard let selectedElapsed, !summary.curvePoints.isEmpty else { return nil }
        return summary.curvePoints.min(by: {
            abs($0.elapsedMinutes - selectedElapsed) < abs($1.elapsedMinutes - selectedElapsed)
        })
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let peakPoint = summary.curvePoints.max(by: { $0.powerKw < $1.powerKw })

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. 顶部成就徽标与本次充电概述
                    headerCard(palette: palette)
                        .opacity(cardsVisible ? 1 : 0)
                        .offset(y: cardsVisible ? 0 : 12)
                        .animation(.spring(duration: 0.45, bounce: 0.25), value: cardsVisible)

                    // 2. 核心三维度数据卡（充电时长 / 增加续航 / 峰值均功）
                    HStack(spacing: 10) {
                        metricBox(
                            title: "充电时长",
                            value: "\(summary.durationMinutes) 分钟",
                            footnote: String(format: "约 %.1f kWh", summary.addedEnergyKwh),
                            palette: palette
                        )
                        metricBox(
                            title: "增加续航",
                            value: "+\(Int(summary.addedRangeKm.rounded())) km",
                            footnote: "\(Int(summary.startSoc.rounded()))% → \(Int(summary.endSoc.rounded()))%",
                            highlight: true,
                            palette: palette
                        )
                        metricBox(
                            title: "峰值功率",
                            value: String(format: "%.1f kW", summary.peakPowerKw),
                            footnote: String(format: "均功 %.1f kW", summary.averagePowerKw),
                            palette: palette
                        )
                    }
                    .opacity(cardsVisible ? 1 : 0)
                    .offset(y: cardsVisible ? 0 : 14)
                    .animation(.spring(duration: 0.52, bounce: 0.2).delay(0.08), value: cardsVisible)

                    // 3. 流畅展开的本次充电功率曲线
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("本次充电功率曲线")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(palette.ink)
                                Text("沿曲线左右滑动可查看对应时刻功率与电量")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            if let pt = selectedPoint ?? peakPoint {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.1f kW", pt.powerKw))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(palette.good)
                                    Text("第 \(Int(pt.elapsedMinutes.rounded())) 分 · \(Int(pt.soc.rounded()))%")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(palette.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(palette.good.opacity(0.12)))
                            }
                        }

                        Chart(summary.curvePoints) { pt in
                            AreaMark(
                                x: .value("时长(分)", pt.elapsedMinutes),
                                y: .value("功率(kW)", pt.powerKw)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [palette.good.opacity(0.34), palette.good.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("时长(分)", pt.elapsedMinutes),
                                y: .value("功率(kW)", pt.powerKw)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(palette.good)

                            if let highlight = selectedPoint ?? peakPoint, highlight.id == pt.id {
                                PointMark(
                                    x: .value("时长(分)", pt.elapsedMinutes),
                                    y: .value("功率(kW)", pt.powerKw)
                                )
                                .symbolSize(selectedPoint == nil ? 58 : 76)
                                .foregroundStyle(palette.good)
                            }
                        }
                        .frame(height: 196)
                        .chartXAxisLabel("分钟")
                        .chartYAxisLabel("kW")
                        .chartXSelection(value: $selectedElapsed)
                        .mask(
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: geo.size.width * chartRevealProgress)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        )
                    }
                    .lingpaoCard(padding: 14)
                    .opacity(cardsVisible ? 1 : 0)
                    .offset(y: cardsVisible ? 0 : 18)
                    .animation(.spring(duration: 0.56, bounce: 0.16).delay(0.14), value: cardsVisible)

                    Button {
                        dismiss()
                    } label: {
                        Text("完成查看")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.good))
                    }
                    .accessibilityIdentifier("charge_summary_dismiss")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 26)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("充电总结报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(palette.secondary)
                    }
                    .accessibilityLabel("关闭充电总结")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            cardsVisible = true
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.95).delay(0.16)) {
                chartRevealProgress = 1.0
            }
        }
    }

    @ViewBuilder
    private func headerCard(palette: LingpaoPalette) -> some View {
        let df: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f
        }()

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(palette.good.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: summary.isCompletedNormally ? "checkmark.seal.fill" : "bolt.circle.fill")
                    .font(.title2)
                    .foregroundStyle(palette.good)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.isCompletedNormally ? "本次充电已完成" : "已停止充电")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.ink)
                Text("\(summary.vehicleName) · \(df.string(from: summary.startTime)) - \(df.string(from: summary.endTime))")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .lingpaoCard(padding: 14)
    }

    @ViewBuilder
    private func metricBox(
        title: String,
        value: String,
        footnote: String,
        highlight: Bool = false,
        palette: LingpaoPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(highlight ? palette.good : palette.ink)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(footnote)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lingpaoCard(padding: 12)
    }
}
