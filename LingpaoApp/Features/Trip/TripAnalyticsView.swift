import Charts
import LingpaoCore
import MapKit
import SwiftUI

/// Tab 3「出行」页：车辆位置与一键导航寻车、底盘拍照、近 7 天里程能耗图表与周能耗拆解
public struct TripAnalyticsView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isChassisPhotoPresented: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let lat = viewModel.telemetry.latitude ?? 30.2084
        let lon = viewModel.telemetry.longitude ?? 120.2121
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        VStack(alignment: .leading, spacing: 0) {
            // 固定页面顶部标题（右侧接入全局多车切换胶囊），防止内容滚动穿透状态栏
            HStack(alignment: .center) {
                Text("出行与能耗")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.ink)
                Spacer()
                GlobalVehicleChip(viewModel: viewModel)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. 地图定位与多端导航寻车卡
                VStack(alignment: .leading, spacing: 10) {
                    Map(position: $cameraPosition) {
                        Marker(viewModel.selectedVehicle?.vehicleName ?? "我的零跑", coordinate: coord)
                            .tint(palette.good)
                    }
                    .frame(height: 175)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onAppear {
                        cameraPosition = .region(
                            MKCoordinateRegion(
                                center: coord,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                        )
                    }

                    Text(viewModel.locationWeather?.formattedAddress ?? String(format: "经纬度 %.5f, %.5f", lat, lon))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.ink)

                    HStack(spacing: 8) {
                        navButton("高德导航", icon: "location.north.fill", palette: palette) {
                            if let url = URL(string: "iosamap://viewMap?sourceApplication=Lingpao&poiname=Car&lat=\(lat)&lon=\(lon)&dev=0") {
                                openURL(url)
                            }
                        }
                        navButton("百度地图", icon: "map.fill", palette: palette) {
                            if let url = URL(string: "baidumap://map/marker?location=\(lat),\(lon)&title=Car&src=Lingpao") {
                                openURL(url)
                            }
                        }
                        navButton("Apple 地图", icon: "safari.fill", palette: palette) {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                            item.name = viewModel.selectedVehicle?.vehicleName ?? "零跑爱车"
                            item.openInMaps()
                        }
                        navButton("底盘拍照", icon: "camera.viewfinder", palette: palette) {
                            Task { await viewModel.fetchChassisPhotoIfNeeded() }
                            isChassisPhotoPresented = true
                        }
                    }
                }
                .lingpaoCard(padding: 14)

                // 2. Swift Charts 近 7 天里程柱状图
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("近 7 日行车里程")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        let totalKm = viewModel.weeklyMetrics.reduce(0) { $0 + $1.mileageKm }
                        Text(String(format: "合计 %.1f km", totalKm))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.good)
                    }

                    if viewModel.weeklyMetrics.isEmpty {
                        Text("暂无近期行驶数据，可下拉刷新同步")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        Chart(viewModel.weeklyMetrics) { item in
                            BarMark(
                                x: .value("日期", item.dateLabel),
                                y: .value("里程", item.mileageKm)
                            )
                            .foregroundStyle(palette.good.gradient)
                            .cornerRadius(6)
                        }
                        .frame(height: 170)
                        .chartYAxisLabel("km")
                    }
                }
                .lingpaoCard(padding: 14)

                // 3. 上周能耗构成与排行卡
                let comp = viewModel.energyComposition
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("上周能耗构成")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Text("领先 \(comp.rankPercentile)% 车友")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(palette.good)
                            .background(Capsule().fill(palette.good.opacity(0.14)))
                    }

                    energyProgressRow(label: "行驶驱动", kwh: comp.drivingKwh, total: comp.totalKwh, color: palette.good, palette: palette)
                    energyProgressRow(label: "空调座舱", kwh: comp.climateKwh, total: comp.totalKwh, color: Color(hex: 0x365B91), palette: palette)
                    energyProgressRow(label: "电池热管理", kwh: comp.batteryThermalKwh, total: comp.totalKwh, color: palette.warning, palette: palette)
                    energyProgressRow(label: "驻车与待机", kwh: comp.standbyAndOtherKwh, total: comp.totalKwh, color: palette.secondary, palette: palette)
                }
                .lingpaoCard(padding: 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            }
            .clipped()
        }
        .sheet(isPresented: $isChassisPhotoPresented) {
            NavigationStack {
                VStack(spacing: 16) {
                    if let photo = viewModel.chassisPhoto, let url = URL(string: photo.fileURL) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                        } placeholder: {
                            ProgressView()
                        }
                        .padding()
                    } else {
                        ContentUnavailableView(
                            "暂无车端底盘泊车图",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("车机未上报底盘留存图，或当前处于演示模式。")
                        )
                    }
                }
                .navigationTitle("车底停车留存图")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { isChassisPhotoPresented = false }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func navButton(_ title: String, icon: String, palette: LingpaoPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(palette.ink)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.background))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func energyProgressRow(label: String, kwh: Double, total: Double, color: Color, palette: LingpaoPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(palette.secondary)
                Spacer()
                Text(String(format: "%.1f kWh (%.0f%%)", kwh, (kwh / total) * 100))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.ink)
            }
            ProgressView(value: kwh, total: total)
                .tint(color)
        }
    }
}
