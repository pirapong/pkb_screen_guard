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

    // Android: เปิด FLAG_SECURE
    await PkbScreenGuard.enableSecure();
    // ถ้าอยากให้ Android auto-monitor ด้วย
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
        ? 'กำลังตรวจสอบ...'
        : (_rooted == true
        ? 'ตรวจพบ Root/Jailbreak (heuristic)'
        : 'ไม่พบ Root/Jailbreak');

    return Scaffold(
      appBar: AppBar(
        title: const Text('pkb_screen_guard Example'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'สถานะอุปกรณ์',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.security),
              const SizedBox(width: 8),
              Expanded(child: Text(rootedText)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Events ล่าสุด',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_events.isEmpty)
            const Text('ยังไม่มี event (ลองอัดหน้าจอ / แชร์หน้าจอ / cast ดู)')
          else
            ..._events.take(30).map(_buildEventTile),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _initGuard,
            child: const Text('Re-init Guard'),
          ),
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
          'time: $ts'
              '${pkg != null ? '\npackage: $pkg' : ''}'
              '${score != null ? '\nscore: $score' : ''}',
        ),
      ),
    );
  }
}
