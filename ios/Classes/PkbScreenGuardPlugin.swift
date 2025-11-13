import Flutter
import UIKit

public class PkbScreenGuardPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?
    private var overlayWindow: UIWindow?

    // Observer tokens
    private var screenCaptureObserver: NSObjectProtocol?
    private var isMonitoring = false

    // MARK: - Register Plugin

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

        // ⭐ Auto start monitoring
        instance.startMonitoringInternal()

        print("[pkb_screen_guard] Plugin registered & auto-monitoring started")
    }

    // MARK: - Flutter MethodChannel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("[pkb_screen_guard] method call: \(call.method)")
        switch call.method {
        case "enableSecure":
            result(nil) // iOS ไม่มี FLAG_SECURE แบบ Android
        case "disableSecure":
            result(nil)
        case "startMonitoring":
            startMonitoringInternal()
            result(nil)
        case "stopMonitoring":
            stopMonitoringInternal()
            result(nil)
        case "showOverlay":
            showOverlay()
            result(nil)
        case "hideOverlay":
            hideOverlay()
            result(nil)
        case "checkRooted":
            result(isDeviceJailbroken())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - EventChannel

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    private func sendEvent(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }

    // MARK: - Monitoring

    func startMonitoringInternal() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let center = NotificationCenter.default

        if #available(iOS 11.0, *) {
            screenCaptureObserver = center.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: nil,
                queue: OperationQueue.main
            ) { [weak self] _ in
                self?.handleScreenCaptureChanged()
            }
        }

        center.addObserver(
            self,
            selector: #selector(screenDidConnect),
            name: UIScreen.didConnectNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(screenDidDisconnect),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )

        handleScreenCaptureChanged()
        handleExternalDisplayChanged()

        print("[pkb_screen_guard] startMonitoringInternal()")
    }

    func stopMonitoringInternal() {
        guard isMonitoring else { return }
        isMonitoring = false

        let center = NotificationCenter.default
        center.removeObserver(self, name: UIScreen.didConnectNotification, object: nil)
        center.removeObserver(self, name: UIScreen.didDisconnectNotification, object: nil)

        if let obs = screenCaptureObserver {
            center.removeObserver(obs)
            screenCaptureObserver = nil
        }

        print("[pkb_screen_guard] stopMonitoringInternal()")
    }

    // MARK: - Screen Capture Handling

    private func handleScreenCaptureChanged() {
        if #available(iOS 11.0, *) {
            let captured = UIScreen.main.isCaptured
            if captured {
                print("[pkb_screen_guard] Screen is captured")
                sendEvent(["event": "screenCaptured"])
                showOverlay()
            } else {
                print("[pkb_screen_guard] Screen capture stopped")
                sendEvent(["event": "screenCapturingStopped"])
                hideOverlay()
            }
        }
    }

    // MARK: - External Display Handling

    @objc private func screenDidConnect() {
        print("[pkb_screen_guard] External display connected")
        handleExternalDisplayChanged()
    }

    @objc private func screenDidDisconnect() {
        print("[pkb_screen_guard] External display disconnected")
        handleExternalDisplayChanged()
    }

    private func handleExternalDisplayChanged() {
        let screens = UIScreen.screens
        if screens.count > 1 {
            print("[pkb_screen_guard] externalDisplayAttached")
            sendEvent(["event": "externalDisplayAttached"])
            showOverlay()
        } else {
            print("[pkb_screen_guard] externalDisplayDetached")
            sendEvent(["event": "externalDisplayDetached"])
            if #available(iOS 11.0, *) {
                if !UIScreen.main.isCaptured {
                    hideOverlay()
                }
            } else {
                hideOverlay()
            }
        }
    }

    // MARK: - Jailbreak Detection (Heuristic)

    private func isDeviceJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let fileManager = FileManager.default
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]

        for path in jailbreakPaths {
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }

        let testPath = "/private/pkb_jb_test.txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try fileManager.removeItem(atPath: testPath)
            return true
        } catch {
        }

        return false
        #endif
    }

    // MARK: - Overlay (จอดำ + ข้อความเตือน)

    private func showOverlay() {
        DispatchQueue.main.async {
            if self.overlayWindow == nil {

                var window: UIWindow

                if #available(iOS 13.0, *) {
                    let scenes = UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .filter { $0.activationState == .foregroundActive }

                    if let scene = scenes.first {
                        window = UIWindow(windowScene: scene)
                        window.frame = scene.coordinateSpace.bounds
                    } else {
                        window = UIWindow(frame: UIScreen.main.bounds)
                    }
                } else {
                    window = UIWindow(frame: UIScreen.main.bounds)
                }

                window.windowLevel = UIWindow.Level.alert + 1
                window.backgroundColor = UIColor.clear

                let maskView = UIView(frame: window.bounds)
                maskView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                maskView.backgroundColor = UIColor.black

                let label = UILabel()
                label.text = "ไม่อนุญาตให้บันทึกหน้าจอหรือแชร์หน้าจอ\nระหว่างใช้งานแอปนี้"
                label.textColor = UIColor.white
                label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
                label.textAlignment = .center
                label.numberOfLines = 0
                label.translatesAutoresizingMaskIntoConstraints = false

                maskView.addSubview(label)

                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: maskView.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: maskView.centerYAnchor),
                    label.leadingAnchor.constraint(equalTo: maskView.leadingAnchor, constant: 24),
                    label.trailingAnchor.constraint(equalTo: maskView.trailingAnchor, constant: -24)
                ])

                window.isUserInteractionEnabled = true

                window.addSubview(maskView)
                window.isHidden = false
                self.overlayWindow = window
            } else {
                self.overlayWindow?.isHidden = false
            }

            print("[pkb_screen_guard] showOverlay()")
        }
    }

    private func hideOverlay() {
        DispatchQueue.main.async {
            self.overlayWindow?.isHidden = true
            print("[pkb_screen_guard] hideOverlay()")
        }
    }
}
