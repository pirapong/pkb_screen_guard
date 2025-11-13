# pkb_screen_guard

`pkb_screen_guard` is a Flutter plugin that helps protect sensitive screens from:

- Screenshots & recent-app previews
- Screen recording
- Screen mirroring / casting (external displays)
- Remote-control tools (heuristic)
- Rooted / jailbroken devices (heuristic)

It is designed for high-security applications such as:

- Banking / fintech apps
- Cooperative / credit union apps
- Enterprise / internal business apps
- Any app that must pass security / penetration testing

Supports **Android** and **iOS**.

## ✨ Features

| Feature                                       | Android                                | iOS                                      |
|----------------------------------------------|----------------------------------------|------------------------------------------|
| Block screenshots & recent-app previews      | ✔ via `FLAG_SECURE`                    | ✔ via black overlay when captured       |
| Detect screen recording                      | ✔ heuristic                            | ✔ via `UIScreen.main.isCaptured`        |
| Detect screen mirroring / casting            | ✔ via `DisplayManager`                 | ✔ via external display detection        |
| Detect external displays                     | ✔                                      | ✔                                        |
| Black overlay with warning text              | ✔ fullscreen overlay view              | ✔ fullscreen overlay `UIWindow`         |
| Root / jailbreak detection (heuristic)       | ✔ multiple checks                      | ✔ multiple checks                        |
| Hook / Frida / Xposed detection (heuristic)  | ✔ basic file/process heuristics        | (Not exposed directly)                  |
| Remote-control app detection (heuristic)     | ✔ package-based detection              | via screen-capture state                |
| Event stream → Flutter                       | ✔ `EventChannel`                       | ✔ `EventChannel`                        |

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  pkb_screen_guard: ^0.0.1
```

Then:

```
flutter pub get
```

## 🚀 Quick Start

### Initialize in `main.dart`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await PkbScreenGuard.enableSecure();  // Android only
  await PkbScreenGuard.startMonitoring();

  runApp(const MyApp());
}
```

## 📡 Listen to security events

```dart
PkbScreenGuard.events().listen((event) {
  debugPrint('pkb_screen_guard event: $event');
});
```

Possible events:

```json
{
  "event": "screenCaptured"
}
{
  "event": "screenCapturingStopped"
}
{
  "event": "externalDisplayAttached"
}
{
  "event": "externalDisplayDetached"
}
{
  "event": "remoteAppDetected",
  "package": "com.teamviewer.teamviewer.market.mobile"
}
{
  "event": "rootDetected",
  "score": 10
}
{
  "event": "hookDetected"
}
```

## 🛡 Root / Jailbreak check

```dart
final rooted = await PkbScreenGuard.checkRooted();
```

## 📘 Full Example

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pkb_screen_guard/pkb_screen_guard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pkb_screen_guard Demo',
      theme: ThemeData(useMaterial3: true),
      home: const GuardHomePage(),
    );
  }
}

class GuardHomePage extends StatefulWidget {
  const GuardHomePage({super.key});

  @override
  State<GuardHomePage> createState() => _GuardHomePageState();
}

class _GuardHomePageState extends State<GuardHomePage> {
  bool? _rooted;
  final List<Map<String, dynamic>> _events = [];
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _initGuard();
  }

  Future<void> _initGuard() async {
    final rooted = await PkbScreenGuard.checkRooted();
    setState(() {
      _rooted = rooted;
    });

    _sub ??= PkbScreenGuard.events().listen((event) {
      setState(() {
        _events.insert(0, {
          'ts': DateTime.now().toIso8601String(),
          ...event,
        });
      });
    });

    await PkbScreenGuard.enableSecure();
    await PkbScreenGuard.startMonitoring();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rootedText = _rooted == null
        ? 'Checking device security...'
        : (_rooted == true
            ? 'Root / Jailbreak detected'
            : 'No root / jailbreak detected');

    return Scaffold(
      appBar: AppBar(
        title: const Text('pkb_screen_guard Example'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Device status: $rootedText'),
          const Divider(),
          const Text('Recent events:'),
          ..._events.map(_eventTile),
        ],
      ),
    );
  }

  Widget _eventTile(Map<String, dynamic> e) {
    return Card(
      child: ListTile(
        title: Text('${e["event"]}'),
        subtitle: Text('${e["ts"]}'),
      ),
    );
  }
}
```

## 🧱 Architecture Overview

### Android
- Uses FLAG_SECURE
- Root detection (test-keys, su paths)
- Hook detection (Frida/Xposed heuristics)
- Remote-control app detection via package scan
- External display detection
- Black overlay using a fullscreen view

### iOS
- Detects screen recording via `isCaptured`
- External display detection via `UIScreen` notifications
- Jailbreak heuristic detection
- Black overlay using a top-level `UIWindow`

## ⚠️ Disclaimer

This plugin improves app security but **cannot guarantee absolute protection**.
Use it as a **defense-in-depth** layer along with backend validation.

## 📄 License

MIT (or your chosen license)
