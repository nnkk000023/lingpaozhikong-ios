import LingpaoCore
import SwiftUI
import WebKit

/// 极验 v4（`gt4.js`）交互验证弹窗封装，完全对齐安卓端 `C0520Tx` 桥接协议
public struct GeetestCaptchaSheet: View {
    public let challenge: GeetestChallenge
    public let onSuccess: (GeetestValidateResult) -> Void
    public let onCancel: () -> Void
    public let onError: (String) -> Void

    @State private var statusMessage: String = "正在加载极验安全验证..."

    public init(
        challenge: GeetestChallenge,
        onSuccess: @escaping (GeetestValidateResult) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.challenge = challenge
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        self.onError = onError
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                GeetestWebViewRepresentable(
                    challenge: challenge,
                    onStatusChange: { statusMessage = $0 },
                    onSuccess: onSuccess,
                    onCancel: onCancel,
                    onError: onError
                )
            }
            .navigationTitle("安全验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
        }
    }
}

private struct GeetestWebViewRepresentable: UIViewRepresentable {
    let challenge: GeetestChallenge
    let onStatusChange: (String) -> Void
    let onSuccess: (GeetestValidateResult) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "geetestBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        let html = GeetestHTMLBuilder.buildHTML(challenge: challenge)
        webView.loadHTMLString(html, baseURL: URL(string: LeapAPIClient.Host.legacyUser))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let parent: GeetestWebViewRepresentable

        init(_ parent: GeetestWebViewRepresentable) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "geetestBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }
            let payload = body["payload"] as? [String: Any] ?? [:]
            DispatchQueue.main.async {
                switch type {
                case "success":
                    let res = GeetestValidateResult(
                        lotNumber: (payload["lot_number"] as? String) ?? "",
                        passToken: (payload["pass_token"] as? String) ?? "",
                        genTime: (payload["gen_time"] as? String) ?? "",
                        captchaOutput: (payload["captcha_output"] as? String) ?? "",
                        requestId: self.parent.challenge.requestId
                    )
                    self.parent.onSuccess(res)
                case "close":
                    self.parent.onCancel()
                case "error":
                    let msg = (payload["message"] as? String) ?? "极验验证失败"
                    self.parent.onStatusChange(msg)
                    self.parent.onError(msg)
                default:
                    break
                }
            }
        }
    }
}
