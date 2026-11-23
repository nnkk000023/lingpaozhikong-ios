import LingpaoCore
import SwiftUI
import UIKit

/// 主工作台壳容器：底层共享车模动画舞台 + 上层 4 Tab 内容 + 底部悬浮胶囊导航栏 + 操控密码弹窗
public struct MainShellView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var navNamespace

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)

        ZStack(alignment: .bottom) {
            palette.background.ignoresSafeArea()

            // 背景：共享汽车 3D/俯视交互舞台（随 activeTab / isChargeSheetPresented / 控车上滑展开丝滑位移与旋转）
            InteractiveCarStageView(
                assets: viewModel.loadedCarAssets,
                telemetry: viewModel.telemetry,
                stage: viewModel.currentStageRoute,
                selectedTarget: viewModel.selectedCabinTarget,
                lightFlashOpacity: viewModel.lightFlashOpacity,
                isInteractiveCabin: viewModel.activeTab == .car && !viewModel.isChargeSheetPresented,
                isCabinLandscape: viewModel.isCabinDockExpanded,
                onSelectTarget: { target in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(duration: 0.25)) {
                        viewModel.selectedCabinTarget = (viewModel.selectedCabinTarget == target) ? nil : target
                    }
                }
            )
            .ignoresSafeArea(edges: .bottom)

            // 前景：当前 Tab 内容视图（充电页打开时隐藏常规 Tab，切换至充电详情交互层）
            Group {
                if viewModel.isChargeSheetPresented {
                    ChargeDetailView(viewModel: viewModel)
                } else {
                    switch viewModel.activeTab {
                    case .home:
                        HomeDashboardView(viewModel: viewModel)
                    case .car:
                        CabinControlView(viewModel: viewModel)
                    case .route:
                        TripAnalyticsView(viewModel: viewModel)
                    case .user, .charge:
                        SettingsView(viewModel: viewModel)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, viewModel.isChargeSheetPresented ? 0 : 76)

            // 底部悬浮胶囊导航栏（复刻原版 `AbstractC1793nc0` 风格）
            if !viewModel.isChargeSheetPresented {
                floatingCapsuleNavBar(palette: palette)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
        // Toast 下移至底部导航栏上方，避免遮挡顶部返回与蓝牙操作按钮
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                ToastBannerView(message: toast)
                    .padding(.bottom, viewModel.isChargeSheetPresented ? 24 : 88)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $viewModel.isPinPromptPresented) {
            PinPromptSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isBleSheetPresented) {
            BleKeyControlSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isVehicleGaragePresented) {
            VehicleGarageSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.completedChargeSummary) { summary in
            ChargeSummarySheet(summary: summary)
        }
    }

    @ViewBuilder
    private func floatingCapsuleNavBar(palette: LingpaoPalette) -> some View {
        let tabs: [(route: AppStageRoute, label: String, icon: String)] = [
            (.home, "车况", "car.fill"),
            (.car, "控车", "slider.horizontal.3"),
            (.route, "出行", "map.fill"),
            (.user, "我的", "person.crop.circle.fill")
        ]

        HStack(spacing: 6) {
            ForEach(tabs, id: \.route) { item in
                let isSelected = viewModel.activeTab == item.route
                Button {
                    withAnimation(.spring(duration: 0.36, bounce: 0.2)) {
                        if item.route != .car {
                            viewModel.isCabinDockExpanded = false
                            viewModel.selectedCabinTarget = nil
                        }
                        viewModel.activeTab = item.route
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .semibold))
                        if isSelected {
                            Text(item.label)
                                .font(.subheadline.weight(.semibold))
                                .matchedGeometryEffect(id: "tabText", in: navNamespace)
                        }
                    }
                    .foregroundStyle(isSelected ? palette.ink : palette.inactive)
                    .padding(.horizontal, isSelected ? 16 : 14)
                    .padding(.vertical, 11)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(palette.background)
                                .matchedGeometryEffect(id: "tabPill", in: navNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(palette.card.opacity(0.94))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.09), radius: 18, x: 0, y: 6)
        )
        .overlay(
            Capsule()
                .stroke(palette.line, lineWidth: 0.8)
        )
    }
}

/// 4 位远程控车 PIN 输入弹窗
private struct PinPromptSheet: View {
    @Bindable var viewModel: AppViewModel
    @State private var enteredPin: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(hex: 0x1FA463))

                Text("输入车辆 4 位远程操控密码")
                    .font(.headline)

                Text("密码将通过 AES-128-CBC 加密后仅随指令发送，并安全缓存在系统 Keychain。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SecureField("请输入 4-8 位操控密码", text: $enteredPin)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .multilineTextAlignment(.center)

                Button("确认并立即执行") {
                    viewModel.confirmPinAndExecute(enteredPin)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x1FA463))
                .disabled(enteredPin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(.top, 28)
            .navigationTitle("安全确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.pendingCommandForPin = nil
                        viewModel.isPinPromptPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
