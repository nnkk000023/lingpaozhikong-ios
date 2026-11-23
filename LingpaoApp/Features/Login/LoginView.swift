import LingpaoCore
import SwiftUI

/// 登录页：展示前 3/4 透明主视觉车图，提供手机号验证码+极验、原始 Auth 凭据导入与离线演示三大入口
public struct LoginView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var phone: String = ""
    @State private var smsCode: String = ""
    @State private var manualSmId: String = ""
    @State private var isAdvancedExpanded: Bool = false
    @State private var isRawImportPresented: Bool = false
    @State private var rawAuthText: String = ""
    @State private var rawPhoneText: String = ""
    @State private var heroImage: UIImage?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 顶部 3/4 主视觉车图
                    VStack(spacing: 8) {
                        if let heroImage {
                            Image(uiImage: heroImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 190)
                                .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
                        } else {
                            Image(systemName: "car.front.waves.up.fill")
                                .font(.system(size: 68))
                                .foregroundStyle(palette.good)
                                .frame(height: 160)
                        }

                        Text("零跑智控")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(palette.ink)

                        Text("个人自用 iOS 原生重制版 · Metal & CoreBluetooth 驱动")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                    }
                    .padding(.top, 12)

                    // 登录表单卡片
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "iphone")
                                .foregroundStyle(palette.secondary)
                            TextField("输入 11 位手机号", text: $phone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .foregroundStyle(palette.ink)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.background))

                        HStack(spacing: 10) {
                            Image(systemName: "number.square")
                                .foregroundStyle(palette.secondary)
                            TextField("输入 6 位短信验证码", text: $smsCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .foregroundStyle(palette.ink)

                            Button {
                                Task { await viewModel.sendSMSCode(phone: phone) }
                            } label: {
                                Text(viewModel.smsCountdownSeconds > 0 ? "\(viewModel.smsCountdownSeconds)s" : "获取验证码")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(viewModel.smsCountdownSeconds > 0 ? palette.inactive : palette.good)
                            }
                            .disabled(viewModel.smsCountdownSeconds > 0 || viewModel.isBusy || phone.count < 11)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.background))

                        // 数美配置提示与可选手动 smDeviceId 折叠区
                        DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ShumeiDeviceProvider.hasNativeSDK ? "已集成数美官方 iOS SDK（自动生成设备标识）" : "当前工程未链接数美 XCFramework：可手动填写已有 smDeviceId，或直接点击下方「导入原始凭据」跳过短信与风控。")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondary)

                                TextField("可选：粘贴数美 smDeviceId（如 B...）", text: $manualSmId)
                                    .font(.caption)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.background))
                            }
                            .padding(.top, 6)
                        } label: {
                            Label("风控设备标识高级选项", systemImage: "shield.lefthalf.filled")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.secondary)
                        }

                        Button {
                            Task {
                                await viewModel.submitPhoneLogin(
                                    phone: phone,
                                    smsCode: smsCode,
                                    manualSmDeviceId: manualSmId
                                )
                            }
                        } label: {
                            HStack {
                                if viewModel.isBusy {
                                    ProgressView().tint(.white)
                                }
                                Text("手机号登录")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.good))
                        }
                        .disabled(viewModel.isBusy || phone.isEmpty || smsCode.isEmpty)
                    }
                    .lingpaoCard()

                    // 双兜底快捷入口：Raw Auth 导入 & 离线体验模式
                    VStack(spacing: 12) {
                        Button {
                            rawPhoneText = phone
                            isRawImportPresented = true
                        } label: {
                            Label("导入原始 Auth 凭据（JSON / 抓包头 / 逗号文本）", systemImage: "key.viewfinder")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(palette.ink)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(palette.card)
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
                                )
                        }

                        Button {
                            viewModel.enterDemoMode()
                        } label: {
                            Label("进入离线体验模式（免登录体验 3D 车漆/座舱交互）", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(palette.good)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(palette.good.opacity(0.12))
                                )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(palette.background.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if let toast = viewModel.toastMessage {
                    ToastBannerView(message: toast)
                        .padding(.bottom, 28)
                        .allowsHitTesting(false)
                }
            }
            .sheet(isPresented: $isRawImportPresented) {
                rawImportSheet(palette: palette)
            }
            .sheet(item: Binding(
                get: { viewModel.geetestChallenge.map { GeetestChallengeItem(challenge: $0) } },
                set: { if $0 == nil { viewModel.geetestChallenge = nil } }
            )) { item in
                GeetestCaptchaSheet(
                    challenge: item.challenge,
                    onSuccess: { result in
                        viewModel.geetestChallenge = nil
                        Task {
                            await viewModel.submitPhoneLogin(
                                phone: item.challenge.phone,
                                smsCode: item.challenge.smsCode,
                                manualSmDeviceId: manualSmId,
                                geetestResult: result
                            )
                        }
                    },
                    onCancel: {
                        viewModel.geetestChallenge = nil
                        viewModel.showToast("已取消极验安全验证")
                    },
                    onError: { errMsg in
                        viewModel.geetestChallenge = nil
                        viewModel.showToast("极验出错：\(errMsg)")
                    }
                )
            }
            .task {
                heroImage = CarAssetLoader.shared.loadHero3QImage(
                    for: viewModel.session.selectedCarType,
                    paintId: viewModel.session.selectedPaintId
                )
            }
        }
    }

    @ViewBuilder
    private func rawImportSheet(palette: LingpaoPalette) -> some View {
        NavigationStack {
            Form {
                Section("凭据文本（支持抓包响应 JSON、Header 片段或 accountId,token,refreshToken）") {
                    TextEditor(text: $rawAuthText)
                        .frame(minHeight: 160)
                        .font(.system(.caption, design: .monospaced))
                }
                Section("可选手机号（用于旧 Token 到期后台静默续期）") {
                    TextField("11 位手机号（可留空）", text: $rawPhoneText)
                        .keyboardType(.phonePad)
                }
                Section {
                    Button {
                        isRawImportPresented = false
                        Task { await viewModel.submitRawAuthLogin(rawText: rawAuthText, phone: rawPhoneText) }
                    } label: {
                        Text("立即导入并换取网关会话")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                            .foregroundStyle(palette.good)
                    }
                    .disabled(rawAuthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("导入原始 Auth 凭据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isRawImportPresented = false }
                }
            }
        }
    }
}

private struct GeetestChallengeItem: Identifiable {
    let id = UUID()
    let challenge: GeetestChallenge
}

/// 底部胶囊消息提示条
public struct ToastBannerView: View {
    public let message: String

    public var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .shadow(radius: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
    }
}
