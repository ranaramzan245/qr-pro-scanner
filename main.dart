import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const QRHome(),
    );
  }
}

class QRHome extends StatefulWidget {
  const QRHome({super.key});

  @override
  State<QRHome> createState() => _QRHomeState();
}

class _QRHomeState extends State<QRHome> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

  bool autoCopy = false;
  bool autoOpen = false;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller!.pauseCamera();
    }
    controller!.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("QR Scanner"),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SwitchListTile(
                  title: const Text("Auto Copy"),
                  value: autoCopy,
                  onChanged: (v) => setState(() => autoCopy = v),
                ),
                SwitchListTile(
                  title: const Text("Auto Open URL"),
                  value: autoOpen,
                  onChanged: (v) => setState(() => autoOpen = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;

    controller.scannedDataStream.listen((scanData) {
      final text = scanData.code ?? '';

      if (autoCopy) {
        // Clipboard copy
      }

      if (autoOpen && (text.startsWith("http://") || text.startsWith("https://"))) {
        // URL open
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
