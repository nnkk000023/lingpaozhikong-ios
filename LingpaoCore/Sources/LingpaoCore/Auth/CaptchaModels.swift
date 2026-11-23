import Foundation

/// 极验 v4 验证挑战参数（对齐 `C0468Rx` & `C1833o40.a`）
public struct GeetestChallenge: Equatable, Sendable {
    /// 默认回退极验 `captchaId`（对应反编译 `C1833o40.a`）
    public static let fallbackCaptchaId = "278c775b5dcb8dda2a2f196f60a28a34"

    public let captchaId: String
    public let riskType: String
    public let requestId: String
    public let phone: String
    public let smsCode: String

    public init(
        captchaId: String,
        riskType: String,
        requestId: String,
        phone: String,
        smsCode: String
    ) {
        self.captchaId = captchaId
        self.riskType = riskType
        self.requestId = requestId
        self.phone = phone
        self.smsCode = smsCode
    }

    /// 从服务端返回的 `risk_type` 中提取 32 位十六进制 `captchaId`，未匹配时回退内置常量
    public static func extractCaptchaId(from riskType: String) -> String {
        let segments = riskType.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{32}$") else {
            return fallbackCaptchaId
        }
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return trimmed
            }
        }
        return fallbackCaptchaId
    }
}

/// 极验 v4 验证完成回执（对齐 `C0442Qx`）
public struct GeetestValidateResult: Equatable, Sendable {
    public let lotNumber: String
    public let passToken: String
    public let genTime: String
    public let captchaOutput: String
    public let requestId: String

    public init(
        lotNumber: String,
        passToken: String,
        genTime: String,
        captchaOutput: String,
        requestId: String
    ) {
        self.lotNumber = lotNumber
        self.passToken = passToken
        self.genTime = genTime
        self.captchaOutput = captchaOutput
        self.requestId = requestId
    }

    public var isComplete: Bool {
        !lotNumber.isEmpty && !passToken.isEmpty && !genTime.isEmpty && !captchaOutput.isEmpty && !requestId.isEmpty
    }
}

/// 极验 v4 `WKWebView` 内联 HTML 模板构建器
public enum GeetestHTMLBuilder {
    /// 生成加载 `https://static.geetest.com/v4/gt4.js` 并通过 `webkit.messageHandlers.geetestBridge` 回调的 HTML
    public static func buildHTML(challenge: GeetestChallenge) -> String {
        let escapedCaptchaId = escapeJS(challenge.captchaId)
        let escapedRiskType = escapeJS(challenge.riskType)
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              background: transparent;
              display: flex;
              align-items: center;
              justify-content: center;
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }
            #status {
              color: #5F6474;
              font-size: 14px;
              text-align: center;
            }
          </style>
          <script src="https://static.geetest.com/v4/gt4.js"></script>
        </head>
        <body>
          <div id="captcha-box"><div id="status">正在加载安全验证...</div></div>
          <script>
            (function () {
              function postMsg(type, payload) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.geetestBridge) {
                  window.webkit.messageHandlers.geetestBridge.postMessage({ type: type, payload: payload || {} });
                }
              }
              if (typeof initGeetest4 !== 'function') {
                postMsg('error', { message: '极验脚本加载失败，请检查网络连接' });
                return;
              }
              var config = {
                captchaId: "\(escapedCaptchaId)",
                product: "bind",
                language: "zho",
                protocol: "https://",
                timeout: 8000,
                riskType: "\(escapedRiskType)",
                risk_type: "\(escapedRiskType)"
              };
              initGeetest4(config, function (captchaObj) {
                document.getElementById('status').innerText = '请在弹窗中完成验证';
                captchaObj.onReady(function () {
                  captchaObj.showCaptcha();
                }).onSuccess(function () {
                  var result = captchaObj.getValidate();
                  if (result) {
                    postMsg('success', {
                      lot_number: result.lot_number || '',
                      pass_token: result.pass_token || '',
                      gen_time: result.gen_time || '',
                      captcha_output: result.captcha_output || ''
                    });
                  } else {
                    postMsg('error', { message: '未获取到极验凭据' });
                  }
                }).onError(function (err) {
                  postMsg('error', { message: (err && err.msg) ? err.msg : '极验验证出错' });
                }).onClose(function () {
                  postMsg('close', {});
                });
              });
            })();
          </script>
        </body>
        </html>
        """
    }

    private static func escapeJS(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
