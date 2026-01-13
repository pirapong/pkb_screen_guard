## 0.0.1
- Initial release of pkb_screen_guard.
- Added screen security features for iOS and Android.

## 0.0.2
- Added remote control app detection on Android (e.g. AnyDesk, TeamViewer, QuickSupport).
- Added manual remote status check via `checkRemoteActive`.
- Automatically blocks screen when remote control is detected.
- Improved overlay protection against screen recording and screen sharing.
- Added security events for remote detection via EventChannel.
- Minor stability improvements and internal refactoring.

## 0.0.3
- Added accessibility (A11Y) service detection using whitelist and blacklist strategy.
- Added detection of suspicious accessibility services commonly used for remote control and automation.
- Added manual accessibility status check via `checkAccessibilityServices`.
- Automatically blocks screen when suspicious accessibility services are detected.
- Improved protection against overlay, tapjacking, and screen capture attacks.
- Improved Android 11+ compatibility with package visibility (`<queries>`).
- Minor performance and stability improvements.