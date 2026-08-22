/*
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:math';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/mixin/encrypt_decryt_service.dart';
import 'package:flutter_common/mixin/main_config_manager.dart';
import 'package:flutter_common/mixin/page_common.dart';
import 'package:flutter_common/mixin/syncer_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mixins/github_syncer.dart';
import '../services/pdf_list_syncer_service.dart';
import '../services/pdf_loader_service.dart';

class PdfViewerPage extends StatefulWidget {
  final FlutterSecureStorage secureStorage;
  final SharedPreferences sharedPreferences;
  final MainConfigManager configManager;
  const PdfViewerPage(
    this.secureStorage,
    this.sharedPreferences,
    this.configManager, {
    super.key,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage>
    with
        PageCommon,
        EncryptDecryptService,
        PdfLoaderService,
        SyncerCore,
        GitHubSyncer,
        WidgetsBindingObserver {
  static final String trainingManualPdf = 'training_manual.pdf';
  static final String keyPdfIsTocVisible = 'pdf_is_toc_visible';
  static final String keyActiveFile = 'pdf_active_file';

  late final PdfViewerController _pdfController;
  final _outlineNotifier = ValueNotifier<List<PdfOutlineNode>?>(null);
  final _pdfListUpdateNotifier = ValueNotifier<List<String>>([]);
  final _currentPageNotifier = ValueNotifier<int>(1);
  late final PdfListSyncerService _listSyncerService;

  bool _isTocVisible = true;
  late String _activeFileName;

  @override
  void initState() {
    super.initState();

    _activeFileName =
        sharedPreferences.getString(keyActiveFile) ?? trainingManualPdf;

    _pdfController = PdfViewerController();
    _listSyncerService = PdfListSyncerService(
      widget.secureStorage,
      widget.sharedPreferences,
      _pdfListUpdateNotifier,
    )..initListLoad();
    _init();
  }

  Future<void> _init() async {
    await initPdfLoader();
    _isTocVisible = sharedPreferences.getBool(keyPdfIsTocVisible) ?? true;
  }

  @override
  void setUrlPassword(String url, String password) {}

  @override
  void setCurrentPageNotifier(int value) {
    _currentPageNotifier.value = value;
  }

  @override
  void setOutlineNotifierNull() {
    _outlineNotifier.value = null;
  }

  @override
  FlutterSecureStorage get secureStorage => widget.secureStorage;

  @override
  SharedPreferences get sharedPreferences => widget.sharedPreferences;

  @override
  String get localFileName => _activeFileName;

  @override
  String get keyDocumentLastModified => _activeFileName == trainingManualPdf
      ? PdfLoaderService.keyPdfLastModified
      : 'pdf_${_activeFileName}_last_modified';

  @override
  String get keyDocumentSha => _activeFileName == trainingManualPdf
      ? PdfLoaderService.keyPdfDocumentSha
      : 'pdf_${_activeFileName}_document_sha';

  @override
  String get keyHasSyncDataModified => _activeFileName == trainingManualPdf
      ? PdfLoaderService.keyPdfIsModified
      : 'pdf_${_activeFileName}_is_modified';

  @override
  String get keyLastPdfPage => _activeFileName == trainingManualPdf
      ? PdfLoaderService.keyPdfLastPdfPage
      : 'pdf_${_activeFileName}_last_page';

  @override
  void dispose() {
    disposePdfLoader();
    _listSyncerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || localDecryptedPath == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<List<String>>(
          valueListenable: _pdfListUpdateNotifier,
          builder: (context, allFiles, _) =>
              _listSyncerService.allFiles.isNotEmpty
              ? DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _activeFileName,
                    isExpanded: true,
                    items:
                        _listSyncerService.allFiles
                            .map(
                              (f) => DropdownMenuItem(
                                value: f,
                                child: Text(f, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList()
                          ..add(
                            DropdownMenuItem(
                              value: trainingManualPdf,
                              child: Text(
                                trainingManualPdf,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    onChanged: (v) {
                      if (v != null) switchActiveFile(v);
                    },
                  ),
                )
              : Text(_activeFileName),
        ),
        leading: IconButton(
          icon: Icon(_isTocVisible ? Icons.menu_open : Icons.menu),
          onPressed: () async {
            await widget.sharedPreferences.setBool(
              keyPdfIsTocVisible,
              !_isTocVisible,
            );
            setState(() => _isTocVisible = !_isTocVisible);
          },
        ),
        actions: [
          if (isCheckingNetwork)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: Icon(syncInProgress ? Icons.sync_lock : Icons.sync),
            onPressed: syncInProgress ? null : () => syncData(force: true),
            tooltip: 'Sync document',
          ),
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: 'Upload New Version of Current Document',
            onPressed: () async => pickLocalDocument(),
          ),
          IconButton(
            icon: Icon(Icons.add_circle),
            tooltip: 'Add a new file',
            onPressed: addNewFile,
          ),
          ...getAppBarCommonActions(widget.configManager),
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
              localDecryptedPath!,
              controller: _pdfController,
              initialPageNumber: lastSavedPage,
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
                onPageChanged: (p) async {
                  if (p != null) {
                    _currentPageNotifier.value = p;
                    await sharedPreferences.setInt(keyLastPdfPage, p);
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
    final page = node.dest?.pageNumber ?? 0;

    bool isActive(PdfOutlineNode n) {
      if (n.dest?.pageNumber == activePage) return true;
      return n.children.any(isActive);
    }

    final isCurrentlyReading = isActive(node);

    final widgetTitle = Row(
      children: [
        Expanded(
          child: Text(
            node.title,
            softWrap: true,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isCurrentlyReading
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: isCurrentlyReading ? Colors.blue.shade700 : Colors.black87,
            ),
          ),
        ),
        if (page > 0)
          Text(
            '$page',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
      ],
    );

    if (!hasChildren) {
      return Material(
        color: isCurrentlyReading ? Colors.blue.shade50 : Colors.transparent,
        child: ListTile(
          title: widgetTitle,
          dense: true,
          selected: isCurrentlyReading,
          onTap: () {
            if (node.dest != null) _pdfController.goToDest(node.dest);
          },
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: widgetTitle,
        dense: true,
        initiallyExpanded: true,
        childrenPadding: const EdgeInsets.only(left: 12),
        children: node.children
            .map((childNode) => _buildOutlineItem(childNode, activePage))
            .toList(),
      ),
    );
  }

  Future _extractTableOfContents(PdfDocument doc) async =>
      _outlineNotifier.value = await doc.loadOutline();

  Future<String?> _promptFileName(String defaultFileName) {
    final c = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        bool isValid = false;

        (bool, String?) validate(String value) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) {
            return (false, null);
          }
          var name = trimmed;
          if (!name.toLowerCase().endsWith('.pdf')) name += '.pdf';

          final exists =
              name == trainingManualPdf ||
              _listSyncerService.allFiles.any(
                (f) => f.toLowerCase() == name.toLowerCase(),
              );
          if (exists) {
            errorText = 'File already exists';
            isValid = false;
          } else {
            errorText = null;
            isValid = true;
          }

          return (isValid, errorText);
        }

        final (defaultValid, _) = validate(defaultFileName);
        if (defaultValid) {
          c.text = defaultFileName.toLowerCase().replaceAll(' ', '_');
        } else {
          isValid = false;
          errorText = null;
        }

        return AlertDialog(
          title: const Text('New PDF name'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. $trainingManualPdf',
              errorText: errorText,
            ),
            onChanged: (v) => setState(() => validate(v)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isValid
                  ? () {
                      var name = c.text.trim();
                      if (!name.toLowerCase().endsWith('.pdf')) {
                        name += '.pdf';
                      }
                      Navigator.pop(dialogContext, name);
                    }
                  : null,
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> addNewFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked == null || picked.path == null) return;

    final name = await _promptFileName(picked.name);
    if (name == null) return;
    var fileName = name.trim();
    if (!fileName.toLowerCase().endsWith('.pdf')) fileName += '.pdf';

    await addAdditionalFile(fileName, picked.path!);
    await _listSyncerService.addFile(fileName);
  }

  Future<void> addAdditionalFile(String newFile, String localFilePath) async {
    if (newFile == _activeFileName) return;
    _activeFileName = newFile;
    appEtag = '';
    appSha = '';
    addLocalDocument(localFilePath);
    await widget.sharedPreferences.setString(keyActiveFile, _activeFileName);
    setOutlineNotifierNull();
  }

  Future<void> switchActiveFile(String newFile) async {
    if (newFile == _activeFileName) return;
    _activeFileName = newFile;
    await switchLocalDocument();
    await widget.sharedPreferences.setString(keyActiveFile, _activeFileName);
    setOutlineNotifierNull();
  }
}
