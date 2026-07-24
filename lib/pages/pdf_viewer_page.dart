/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_common/mixin/encrypt_decryt_service.dart';
import 'package:flutter_common/mixin/main_config_manager.dart';
import 'package:flutter_common/mixin/page_common.dart';
import 'package:flutter_common/mixin/syncer_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mixins/github_syncer.dart';
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
  static final String keyPdfIsTocVisible = 'pdf_is_toc_visible';

  late final PdfViewerController _pdfController;
  final _outlineNotifier = ValueNotifier<List<PdfOutlineNode>?>(null);
  final _currentPageNotifier = ValueNotifier<int>(1);

  bool _isTocVisible = true;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
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
  void dispose() {
    disposePdfLoader();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || localDecryptedPath == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isCheckingNetwork ? 'Updating...' : 'Tennis Playbook'),
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
            onPressed: syncInProgress ? null : syncData,
          ),
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: 'Upload New Document',
            onPressed: () async => pickLocalDocument(),
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
                    await sharedPreferences.setInt(
                      PdfLoaderService.keyLastPdfPage,
                      p,
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
    final widgetTitle = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            node.title,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isCurrentlyReading
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: isCurrentlyReading ? Colors.blue.shade700 : Colors.black87,
            ),
          ),
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
