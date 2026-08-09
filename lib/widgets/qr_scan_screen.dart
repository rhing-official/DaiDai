import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// QRコードをカメラで読み取り、検出した生の文字列を`Navigator.pop`で返す
/// だけの薄いラッパー。パース（招待URLか、QRログインのセッションIDかなど）は
/// 呼び出し元が行う（縁結び・QRログインで共用、2026-08-09抽出）。
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({required this.title, super.key});

  final String title;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final rawValue = capture.barcodes.first.rawValue;
    if (rawValue == null) return;
    _handled = true;
    Navigator.of(context).pop(rawValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
