import Flutter
import UIKit
import ReplayKit

public class PkbScreenGuardPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?
    private var shieldView: UIView?
    private var monitoring = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "pkb_screen_guard/methods",
            binaryMessenger: registrar.messenger()
        )

        let event = FlutterEventChannel(
            name: "pkb_screen_guard/events",
            binaryMessenger: registrar.messenger()
        )

        let instance = PkbScreenGuardPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        event.setStreamHandler(instance)
    }

    // MARK: - Method Channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enableSecure":
            enableSecure()
            result(nil)

        case "disableSecure":
            disableSecure()
            result(nil)

        case "showOverlay":
            showOverlay()
            result(nil)

        case "hideOverlay":
            hideOverlay()
            result(nil)

        case "startMonitoring":
            startMonitoring()
            result(nil)

        case "stopMonitoring":
            stopMonitoring()
            result(nil)

        case "checkRemoteActive":
            result(checkRemoteActive())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Secure Setup (สำคัญที่สุด)

    private func enableSecure() {
        createShieldIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenCapturedChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDidTakeScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResign),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    private func disableSecure() {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Create Shield (Bank technique)

    private func createShieldIfNeeded() {
        DispatchQueue.main.async {
            guard self.shieldView == nil,
                  let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first(where: { $0.isKeyWindow }) else {
                return
            }

            let shield = UIView(frame: window.bounds)
            shield.backgroundColor = .black
            shield.alpha = 0
            shield.isUserInteractionEnabled = false

            let label = UILabel()
            label.text = "ไม่อนุญาตให้จับภาพหน้าจอ"
            label.textColor = .white
            label.textAlignment = .center
            label.font = UIFont.boldSystemFont(ofSize: 22)
            label.translatesAutoresizingMaskIntoConstraints = false

            shield.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: shield.centerYAnchor)
            ])

            window.addSubview(shield)
            self.shieldView = shield
        }
    }

    // MARK: - Overlay Control (สลับ alpha เท่านั้น)

    private func showOverlay() {
        DispatchQueue.main.async {
            self.shieldView?.alpha = 1
        }
    }

    private func hideOverlay() {
        DispatchQueue.main.async {
            self.shieldView?.alpha = 0
        }
    }

    // MARK: - Screenshot Detection

    @objc private func userDidTakeScreenshot() {
        showOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.hideOverlay()
        }
        sendEvent(["event": "screenshotDetected"])
    }

    // MARK: - Screen Record / Mirror

    @objc private func screenCapturedChanged() {
        if UIScreen.main.isCaptured {
            showOverlay()
            sendEvent(["event": "screenCaptured"])
        } else {
            hideOverlay()
        }
    }

    // MARK: - App Switcher

    @objc private func appWillResign() {
        showOverlay()
    }

    // MARK: - Monitoring Loop

    private func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true

        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let remote = self.checkRemoteActive()
            if remote["remoteActive"] as? Bool == true {
                self.showOverlay()
                self.sendEvent(["event": "remoteDetected"])
            }
        }
    }

    private func stopMonitoring() {
        monitoring = false
    }

    // MARK: - Remote Detection

    private func checkRemoteActive() -> [String: Any] {
        let screenCaptured = UIScreen.main.isCaptured
        let mirrored = UIScreen.screens.count > 1
        let recording = RPScreenRecorder.shared().isRecording

        return [
            "remoteActive": screenCaptured || mirrored || recording,
            "screenCaptured": screenCaptured,
            "mirroredDisplay": mirrored,
            "isRecording": recording
        ]
    }

    // MARK: - Event Channel

    private func sendEvent(_ map: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(map)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
