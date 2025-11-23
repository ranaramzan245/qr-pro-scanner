// main.dart
import 'dart:convert';
import 'dart:io';
import 'package:clipboard/clipboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() {
  runApp(const QRProApp());
}

class QRProApp extends StatelessWidget {
  const QRProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'qr pro scanner',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A74FF),
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScanEntry {
  final String text;
  final DateTime when;
  ScanEntry({required this.text, required this.when});
  Map<String, dynamic> toJson() => {'text': text, 'when': when.toIso8601String()};
  static ScanEntry fromJson(Map<String, dynamic> j) => ScanEntry(
        text: j['text'] as String,
        when: DateTime.parse(j['when'] as String),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool flashOn = false;
  bool isProcessing = false;
  List<ScanEntry> history = [];
  bool autoCopy = true;
  bool autoOpen = true;
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      autoCopy = prefs?.getBool('autoCopy') ?? true;
      autoOpen = prefs?.getBool('autoOpen') ?? true;
      final raw = prefs?.getStringList('history') ?? [];
      history = raw.map((s) => ScanEntry.fromJson(jsonDecode(s))).toList();
    });
  }

  Future<void> _savePrefs() async {
    if (prefs == null) prefs = await SharedPreferences.getInstance();
    await prefs!.setBool('autoCopy', autoCopy);
    await prefs!.setBool('autoOpen', autoOpen);
    final raw = history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs!.setStringList('history', raw);
  }

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller?.pauseCamera();
      controller?.resumeCamera();
    }
  }

  void _handleScan(String data) async {
    if (isProcessing) return;
    isProcessing = true;
    try {
      final now = DateTime.now();
      final entry = ScanEntry(text: data, when: now);
      setState(() {
        history.insert(0, entry);
      });
      await _savePrefs();

      if (autoCopy) {
        await FlutterClipboard.copy(data);
        Fluttertoast.showToast(msg: 'Copied to clipboard');
      }

      if (autoOpen && _isProbablyUrl(data)) {
        final uri = Uri.parse(data);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      // Show quick dialog with options
      if (mounted) {
        showModalBottomSheet(
            context: context,
            builder: (c) => _buildResultSheet(data),
            isScrollControlled: true);
      }
    } catch (e) {
      if (kDebugMode) print('Handle scan error: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      isProcessing = false;
    }
  }

  Widget _buildResultSheet(String data) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Wrap(children: [
        ListTile(
            title: const Text('Result'),
            subtitle: Text(data, style: const TextStyle(fontWeight: FontWeight.w600))),
        ButtonBar(
          alignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
                onPressed: () {
                  FlutterClipboard.copy(data);
                  Navigator.pop(context);
                  Fluttertoast.showToast(msg: 'Copied');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy')),
            TextButton.icon(
                onPressed: () {
                  ShareHelper.shareText(context, data);
                },
                icon: const Icon(Icons.share),
                label: const Text('Share')),
            TextButton.icon(
                onPressed: () async {
                  if (_isProbablyUrl(data)) {
                    final uri = Uri.parse(data);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      Fluttertoast.showToast(msg: 'Cannot open URL');
                    }
                  } else {
                    Fluttertoast.showToast(msg: 'Not a URL');
                  }
                },
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open')),
          ],
        ),
        const SizedBox(height: 12)
      ]),
    );
  }

  bool _isProbablyUrl(String s) {
    return s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('www.') ||
        Uri.tryParse(s)?.hasAbsolutePath == true && (s.contains('.') || s.contains('/'));
  }

  Future<void> _scanFromGallery() async {
    try {
      final perm = await Permission.photos.request();
      if (!perm.isGranted) {
        Fluttertoast.showToast(msg: 'Gallery permission required');
        return;
      }
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final inputImage = InputImage.fromFilePath(file.path);
      final barcodeScanner = GoogleMlKit.vision.barcodeScanner();
      final barcodes = await barcodeScanner.processImage(inputImage);
      await barcodeScanner.close();
      if (barcodes.isEmpty) {
        Fluttertoast.showToast(msg: 'No QR/Barcode found in image');
        return;
      }
      final raw = barcodes.first.rawValue ?? '';
      _handleScan(raw);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Error scanning image');
      if (kDebugMode) print('Gallery scan error: $e');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      Fluttertoast.showToast(msg: 'Camera permission required');
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF0A74FF); // blue
    return Scaffold(
      appBar: AppBar(
        title: const Text('qr pro scanner'),
        actions: [
          IconButton(
              onPressed: () => _showSettingsDialog(),
              icon: const Icon(Icons.settings)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(children: [
              _buildQRView(),
              Positioned(
                top: 12,
                left: 12,
                child: Card(
                  color: Colors.white70,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(children: [
                      const Icon(Icons.flash_on, size: 18),
                      const SizedBox(width: 6),
                      Text('Flash: ${flashOn ? "on" : "off"}'),
                    ]),
                  ),
                ),
              ),
              Positioned(
                bottom: 18,
                left: 18,
                child: FloatingActionButton.extended(
                    heroTag: 'gal',
                    onPressed: _scanFromGallery,
                    label: const Text('Scan from gallery'),
                    icon: const Icon(Icons.photo)),
              ),
              Positioned(
                bottom: 18,
                right: 18,
                child: FloatingActionButton(
                    heroTag: 'torch',
                    onPressed: () async {
                      await controller?.toggleFlash();
                      final f = await controller?.getFlashStatus();
                      setState(() {
                        flashOn = f ?? false;
                      });
                    },
                    child: const Icon(Icons.flashlight_on)),
              ),
            ]),
          ),
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Settings', style: TextStyle(color: primary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Auto copy to clipboard'),
                      Switch(
                          value: autoCopy,
                          onChanged: (v) {
                            setState(() => autoCopy = v);
                            _savePrefs();
                          })
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Auto open URLs'),
                      Switch(
                          value: autoOpen,
                          onChanged: (v) {
                            setState(() => autoOpen = v);
                            _savePrefs();
                          })
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('History', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextButton(
                          onPressed: () async {
                            setState(() {
                              history.clear();
                            });
                            await _savePrefs();
                          },
                          child: const Text('Clear')),
                    ],
                  ),
                  Expanded(child: _buildHistoryList()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (history.isEmpty) {
      return const Center(child: Text('No scans yet'));
    }
    return ListView.separated(
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, idx) {
        final e = history[idx];
        return ListTile(
          title: Text(e.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${e.when.toLocal()}'),
          trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                FlutterClipboard.copy(e.text);
                Fluttertoast.showToast(msg: 'Copied');
              }),
          onTap: () async {
            // open sheet
            if (autoOpen && _isProbablyUrl(e.text)) {
              final uri = Uri.parse(e.text);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                Fluttertoast.showToast(msg: 'Cannot open URL');
              }
            } else {
              showModalBottomSheet(context: context, builder: (_) => _buildResultSheet(e.text));
            }
          },
        );
      },
    );
  }

  Widget _buildQRView() {
    return FutureBuilder(
      future: Permission.camera.status,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return QRView(
          key: qrKey,
          onQRViewCreated: _onQRViewCreated,
          overlay: QrScannerOverlayShape(
            borderColor: const Color(0xFF0A74FF),
            borderRadius: 10,
            borderLength: 32,
            borderWidth: 8,
            cutOutSize: MediaQuery.of(context).size.width * 0.7,
          ),
        );
      },
    );
  }

  void _onQRViewCreated(QRViewController ctrl) {
    controller = ctrl;
    controller?.scannedDataStream.listen((scanData) {
      _handleScan(scanData.code ?? '');
    });
  }

  void _showSettingsDialog() {
    showDialog(
        context: context,
        builder: (c) {
          return AlertDialog(
            title: const Text('App info & settings'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Version 1.0.'),
              const SizedBox(height: 8),
              const Text('Developed for lightweight, fast scanning.'),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('OK'))
            ],
          );
        });
  }
}

class ShareHelper {
  static void shareText(BuildContext context, String text) {
    // simple fallback using clipboard + toast — because share package requires extra setup
    FlutterClipboard.copy(text);
    Fluttertoast.showToast(msg: 'Text copied. Use paste to share.');
  }
}
