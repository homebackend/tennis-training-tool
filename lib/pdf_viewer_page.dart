import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({super.key});

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late final PdfViewerController _pdfController;
  final _outlineNotifier = ValueNotifier<List<PdfOutlineNode>?>(null);
  final _currentPageNotifier = ValueNotifier<int>(1);
  final _secureStorage = const FlutterSecureStorage();
  final _urlController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isTocVisible = true;
  bool _isLoading = true;
  bool _isCheckingNetwork = false;
  String? _localDecryptedPath;
  int _lastSavedPage = 1;
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _initializeSyncPipeline();
  }

  Future<void> _initializeSyncPipeline() async {
    final prefs = await SharedPreferences.getInstance();
    final url = await _secureStorage.read(key: "pdf_download_url");
    final pass = await _secureStorage.read(key: "pdf_encryption_password");

    if (url != null && pass != null) {
      _urlController.text = url;
      _passwordController.text = pass;
      _lastSavedPage = prefs.getInt('last_pdf_page') ?? 1;
      _currentPageNotifier.value = _lastSavedPage;
      await _syncEncryptedDocument(url, pass);
    } else {
      final path = prefs.getString('last_picked_local_path');
      if (path != null && await File(path).exists()) {
        setState(() {
          _localDecryptedPath = path;
          _lastSavedPage = prefs.getInt('last_pdf_page') ?? 1;
          _currentPageNotifier.value = _lastSavedPage;
        });
      }
    }

    if (mounted) setState(() => _isLoading = false);

    _updateCheckTimer = Timer.periodic(const Duration(minutes: 5), (t) async {
      final u = await _secureStorage.read(key: "pdf_download_url");
      final p = await _secureStorage.read(key: "pdf_encryption_password");
      if (u != null && p != null) {
        _syncEncryptedDocument(u, p, silentCheck: true);
      }
    });
  }

  Future<void> _pickLocalDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_picked_local_path', path);
      await prefs.setInt('last_pdf_page', 1);

      await _secureStorage.delete(key: "pdf_download_url");
      await _secureStorage.delete(key: "pdf_encryption_password");

      setState(() {
        _localDecryptedPath = path;
        _lastSavedPage = 1;
        _currentPageNotifier.value = 1;
        _outlineNotifier.value = null;
      });
    }
  }

  Future<void> _saveConfigAndFetch(String url, String password) async {
    if (url.isEmpty || password.isEmpty) return;
    setState(() => _isLoading = true);
    await _secureStorage.write(key: "pdf_download_url", value: url);
    await _secureStorage.write(key: "pdf_encryption_password", value: password);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pdf_network_etag');
    await prefs.remove('last_picked_local_path');

    await _syncEncryptedDocument(url, password);
    setState(() => _isLoading = false);
  }

  Future<void> _syncEncryptedDocument(
    String url,
    String password, {
    bool silentCheck = false,
  }) async {
    if (!silentCheck) setState(() => _isCheckingNetwork = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final etag = prefs.getString('pdf_network_etag') ?? '';
      final resp = await http.get(
        Uri.parse(url),
        headers: {if (etag.isNotEmpty) 'If-None-Match': etag},
      );

      if (resp.statusCode == 304 && _localDecryptedPath != null) return;
      if (resp.statusCode == 200) {
        final file = File(
          '${(await getApplicationDocumentsDirectory()).path}/playbook.pdf',
        );
        await file.writeAsBytes(await _decryptBytes(resp.bodyBytes, password));
        await prefs.setString(
          'pdf_network_etag',
          resp.headers['etag'] ?? 'valid',
        );
        setState(() {
          _localDecryptedPath = file.path;
          _outlineNotifier.value = null;
        });
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    } finally {
      if (!silentCheck) setState(() => _isCheckingNetwork = false);
    }
  }

  Future<Uint8List> _decryptBytes(Uint8List data, String password) async {
    final salt = data.sublist(0, 16); // Bytes 0 to 15
    final nonce = data.sublist(16, 28); // Bytes 16 to 27
    final macBytes = data.sublist(28, 44); // Bytes 28 to 43 (The MAC tag)
    final ct = data.sublist(44); // Bytes 44 to the end (Ciphertext)

    final derived = await Pbkdf2.hmacSha256(
      iterations: 10000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

    // Pass the real authentication parameters instead of Mac.empty
    return Uint8List.fromList(
      await AesGcm.with256bits().decrypt(
        SecretBox(
          ct,
          nonce: nonce,
          mac: Mac(macBytes), // Provide the extracted validation key
        ),
        secretKey: derived,
      ),
    );
  }

  Future<void> _exportPreferences() async {
    try {
      final p = await SharedPreferences.getInstance();
      final url = await _secureStorage.read(key: "pdf_download_url") ?? "";
      final pass =
          await _secureStorage.read(key: "pdf_encryption_password") ?? "";

      final Map<String, dynamic> configMap = {
        "url": url,
        "password": pass,
        "last_page": p.getInt('last_pdf_page') ?? 1,
        "local_path": p.getString('last_picked_local_path') ?? "",
      };

      final String jsonString = json.encode(configMap);
      final Uint8List fileBytes = Uint8List.fromList(utf8.encode(jsonString));

      // ✅ FIXED: Removed .platform to call the static class method directly
      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: 'Export App Settings',
        fileName: 'tennis_tool_settings.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: fileBytes,
      );

      if (outputPath != null) {
        final File exportFile = File(outputPath);
        await exportFile.writeAsBytes(fileBytes);
        _showSnackBar("Configuration profile saved successfully!");
      }
    } catch (e) {
      _showSnackBar("Failed to export configuration file: $e");
    }
  }

  Future<void> _importPreferences() async {
    try {
      // ✅ FIXED: Removed .platform to call the static class method directly
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final File selectedFile = File(result.files.single.path!);
        final String fileContent = await selectedFile.readAsString();

        final Map<String, dynamic> parsed = json.decode(fileContent);
        final prefs = await SharedPreferences.getInstance();

        if (parsed.containsKey("url") && parsed.containsKey("password")) {
          await _secureStorage.write(
            key: "pdf_download_url",
            value: parsed["url"],
          );
          await _secureStorage.write(
            key: "pdf_encryption_password",
            value: parsed["password"],
          );

          if (parsed["local_path"] != null && parsed["local_path"] != "") {
            await prefs.setString(
              'last_picked_local_path',
              parsed["local_path"],
            );
          } else {
            await prefs.remove('last_picked_local_path');
          }

          await prefs.setInt('last_pdf_page', parsed["last_page"] ?? 1);
          _showSnackBar("Configuration imported! Syncing new playbook...");

          _initializeSyncPipeline();
        } else {
          _showSnackBar(
            "Invalid File: Missing mandatory configuration properties.",
          );
        }
      }
    } catch (e) {
      _showSnackBar("Failed to import configuration: $e");
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _outlineNotifier.dispose();
    _currentPageNotifier.dispose();
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_localDecryptedPath == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Setup')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Decryption Key'),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _saveConfigAndFetch(
                  _urlController.text.trim(),
                  _passwordController.text.trim(),
                ),
                child: const Text('Sync'),
              ),
              ElevatedButton(
                onPressed: _pickLocalDocument,
                child: const Text('Local File'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _importPreferences,
                icon: const Icon(Icons.file_present),
                label: const Text('Import Configuration File'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCheckingNetwork ? 'Updating...' : 'Tennis Playbook'),
        leading: IconButton(
          icon: Icon(_isTocVisible ? Icons.menu_open : Icons.menu),
          onPressed: () => setState(() => _isTocVisible = !_isTocVisible),
        ),
        actions: [
          if (_isCheckingNetwork)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: 'Export Settings',
            onPressed: _exportPreferences,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => setState(() => _localDecryptedPath = null),
          ),
        ],
      ),
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: _isTocVisible ? 280 : 0,
            curve: Curves.easeInOut,
            child: Container(
              color: Colors.grey.shade100,
              child: ValueListenableBuilder<List<PdfOutlineNode>?>(
                valueListenable: _outlineNotifier,
                builder: (context, out, _) {
                  if (out == null) {
                    return const Center(child: Text('Extracting Index...'));
                  }
                  if (out.isEmpty) {
                    return const Center(
                      child: Text('No index structural headers found.'),
                    );
                  }
                  return ValueListenableBuilder<int>(
                    valueListenable: _currentPageNotifier,
                    builder: (context, activePage, _) {
                      return ListView(
                        children: out
                            .map((n) => _buildOutlineItem(n, activePage))
                            .toList(),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: PdfViewer.file(
              _localDecryptedPath!,
              controller: _pdfController,
              initialPageNumber: _lastSavedPage,
              params: PdfViewerParams(
                layoutPages: (pages, params) {
                  final width =
                      pages.fold(0.0, (w, p) => max(w, p.width)) +
                      params.margin * 2;
                  final List<Rect> pageLayout = [];
                  var y = params.margin;
                  for (var page in pages) {
                    pageLayout.add(
                      Rect.fromLTWH(
                        (width - page.width) / 2,
                        y,
                        page.width,
                        page.height,
                      ),
                    );
                    y += page.height + params.margin;
                  }
                  return PdfPageLayout(
                    pageLayouts: pageLayout,
                    documentSize: Size(width, y),
                  );
                },
                sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
                  calculateInitialZoom: (d, c, fit, cover) => cover,
                ),
                onViewerReady: (d, c) => _extractTableOfContents(d),
                onPageChanged: (p) {
                  if (p != null) {
                    _currentPageNotifier.value = p;
                    SharedPreferences.getInstance().then(
                      (s) => s.setInt('last_pdf_page', p),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutlineItem(PdfOutlineNode node, int activePage) {
    final hasChildren = node.children.isNotEmpty;
    final bool isCurrentlyReading = node.dest?.pageNumber == activePage;
    final widgetTitle = Text(
      node.title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: isCurrentlyReading ? FontWeight.bold : FontWeight.normal,
        color: isCurrentlyReading ? Colors.blue.shade700 : Colors.black87,
      ),
    );
    if (!hasChildren) {
      return Material(
        color: isCurrentlyReading ? Colors.blue.shade50 : Colors.transparent,
        child: ListTile(
          title: widgetTitle,
          dense: true,
          selected: isCurrentlyReading,
          onTap: () => _pdfController.goToDest(node.dest),
        ),
      );
    }
    return Material(
      color: isCurrentlyReading
          ? Colors.blue.shade50.withValues(alpha: 0.3)
          : Colors.transparent,
      child: ExpansionTile(
        title: widgetTitle,
        dense: true,
        initiallyExpanded: true,
        childrenPadding: const EdgeInsets.only(left: 12.0),
        children: node.children
            .map((childNode) => _buildOutlineItem(childNode, activePage))
            .toList(),
      ),
    );
  }

  Future _extractTableOfContents(PdfDocument doc) async =>
      _outlineNotifier.value = await doc.loadOutline();
}
