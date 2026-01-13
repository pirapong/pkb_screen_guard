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
      title: 'pkb_screen_guard Example',
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
  PkbOverlayStatus? _overlayStatus;
  PkbAasStatus? _aasStatus;
  Map<String, dynamic>? _remoteStatus;

  final List<Map<String, dynamic>> _events = [];
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _initGuard();
  }

  Future<void> _initGuard() async {
    final rooted = await PkbScreenGuard.checkRooted();
    setState(() => _rooted = rooted);

    _sub ??= PkbScreenGuard.events().listen((event) async {
      setState(() {
        _events.insert(0, {
          'ts': DateTime.now().toIso8601String(),
          ...event,
        });
      });

      if (event['event'] == 'remoteAppDetected') {
        await PkbScreenGuard.showOverlay();

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: const Text('Security warning'),
              content: const Text(
                'Remote screen control detected.\n'
                'This application cannot be used right now.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }

        // SystemNavigator.pop();
      }
    });

    await PkbScreenGuard.enableSecure();
    await PkbScreenGuard.enableSecurityGuard();
    await PkbScreenGuard.startMonitoring();

    _checkOverlay();
    _checkAas();
  }

  Future<void> _checkOverlay() async {
    final status = await PkbScreenGuard.checkOverlayStatus();
    setState(() => _overlayStatus = status);
  }

  Future<void> _checkAas() async {
    final aas = await PkbScreenGuard.checkAccessibilityServices(
      allowedInstallers: [
        'com.android.vending',
        'com.android.packageinstaller',
      ],
      allowedPackages: [],
    );
    setState(() => _aasStatus = aas);
  }

  Future<void> _checkAnyDeskRemote() async {
    final res = await PkbScreenGuard.checkRemoteActive();
    setState(() => _remoteStatus = res);

    if (res['remoteActive'] == true) {
      await PkbScreenGuard.showOverlay();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rootedText = _rooted == null
        ? 'Checking...'
        : (_rooted == true
            ? 'Root / Jailbreak detected'
            : 'No Root / Jailbreak detected');

    final overlayText = _overlayStatus == null
        ? 'Checking...'
        : '''
Draw Over Apps: ${_overlayStatus!.hasOverlay ? "Enabled" : "Disabled"}
Touch Obscured: ${_overlayStatus!.touchObscured ? "Detected" : "Not detected"}
''';

    final aasText = _aasStatus == null
        ? 'Checking...'
        : '''
Suspicious AAS: ${_aasStatus!.hasSuspiciousAas ? "Detected" : "Not detected"}
Packages: ${_aasStatus!.suspiciousPackages.join(", ")}
''';

    return Scaffold(
      appBar: AppBar(
        title: const Text('pkb_screen_guard Example'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Device & Security",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text("Root / Jailbreak"),
            subtitle: Text(rootedText),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.layers),
            title: const Text("Overlay status"),
            subtitle: Text(overlayText),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _checkOverlay,
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.accessibility),
            title: const Text("Accessibility services"),
            subtitle: Text(aasText),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _checkAas,
            ),
          ),
          const Divider(height: 32),
          const Text(
            "Manual actions",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.showOverlay(),
            child: const Text("Show overlay"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.hideOverlay(),
            child: const Text("Hide overlay"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.enableSecure(),
            child: const Text("Enable FLAG_SECURE"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.disableSecure(),
            child: const Text("Disable FLAG_SECURE"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.startMonitoring(),
            child: const Text("Start monitoring"),
          ),
          ElevatedButton(
            onPressed: () => PkbScreenGuard.stopMonitoring(),
            child: const Text("Stop monitoring"),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _checkAnyDeskRemote,
            child: const Text("Check remote activity"),
          ),
          if (_remoteStatus != null)
            Card(
              child: ListTile(
                leading: Icon(
                  _remoteStatus!['remoteActive'] == true
                      ? Icons.warning
                      : Icons.check_circle,
                  color: _remoteStatus!['remoteActive'] == true
                      ? Colors.red
                      : Colors.green,
                ),
                title: Text(
                  _remoteStatus!['remoteActive'] == true
                      ? "Remote activity detected"
                      : "No remote activity detected",
                ),
                subtitle: Text(_remoteStatus.toString()),
              ),
            ),
          const SizedBox(height: 20),
          const Divider(),
          const Text(
            "Latest events",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (_events.isEmpty)
            const Text("No events yet")
          else
            ..._events.take(30).map(_buildEventTile),
        ],
      ),
    );
  }

  Widget _buildEventTile(Map<String, dynamic> e) {
    final ev = e['event'];
    final ts = e['ts'];
    final pkg = e['package'];
    final score = e['score'];

    return Card(
      child: ListTile(
        title: Text('$ev'),
        subtitle: Text(
          "time: $ts"
          "${pkg != null ? "\npackage: $pkg" : ""}"
          "${score != null ? "\nscore: $score" : ""}",
        ),
      ),
    );
  }
}
