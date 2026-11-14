import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 【一時的な診断・原因が分かったら削除する】フレームの時間を1秒ごとに集計して
/// `[DIAG-PERF]`へ出す（`--dart-define=PERF_PROBE=true`、2026-11-14）。通話のミニ表示で、
/// 映像を出すとカクつく原因（UIスレッドかラスタースレッドか）を切り分けるための計測。
const kPerfProbe = bool.fromEnvironment('PERF_PROBE');

/// 画面に出す直近1秒の集計（[PerfProbeOverlay]）。
final ValueNotifier<String> perfProbeText = ValueNotifier<String>('');

/// `PERF_PROBE`の時だけ、画面の左上に直近の集計を重ねる（操作は受けない）。
class PerfProbeOverlay extends StatelessWidget {
  const PerfProbeOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kPerfProbe) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      top: 0,
      child: IgnorePointer(
        child: ValueListenableBuilder<String>(
          valueListenable: perfProbeText,
          builder: (context, text, _) => Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(4),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontSize: 10,
                fontFamily: 'monospace',
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void startPerfProbe() {
  if (!kPerfProbe) return;
  final buildMs = <double>[];
  final rasterMs = <double>[];
  var jank = 0;
  var lastReport = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds / 1000;
      final r = t.rasterDuration.inMicroseconds / 1000;
      buildMs.add(b);
      rasterMs.add(r);
      if (b > 16.7 || r > 16.7) jank++;
    }
    final now = DateTime.now();
    if (now.difference(lastReport) < const Duration(seconds: 1)) return;
    lastReport = now;
    double avg(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    double max(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
    final line =
        'frames=${buildMs.length} '
        'build ${avg(buildMs).toStringAsFixed(1)}/${max(buildMs).toStringAsFixed(1)}ms '
        'raster ${avg(rasterMs).toStringAsFixed(1)}/${max(rasterMs).toStringAsFixed(1)}ms '
        'jank=$jank';
    debugPrint('[DIAG-PERF] $line');
    perfProbeText.value = line;
    buildMs.clear();
    rasterMs.clear();
    jank = 0;
  });
}
