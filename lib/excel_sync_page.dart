/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/biometric_sync_service.dart';
import 'widgets/athlete_analytics_dashboard.dart';
import 'widgets/biometric_dialogs.dart';
import 'widgets/athlete_tracker_setup.dart';
import 'widgets/athlete_selector_bar.dart';
import 'widgets/tracker_data_grid.dart';

class ExcelSyncPage extends StatefulWidget {
  final FlutterSecureStorage secureStorage;
  const ExcelSyncPage(this.secureStorage, {super.key});

  @override
  State<ExcelSyncPage> createState() => _ExcelSyncPageState();
}

class _ExcelSyncPageState extends State<ExcelSyncPage>
    with TickerProviderStateMixin {
  static final String _keyLastSelectedKidId = 'last_selected_kid_id';

  late final BiometricSyncService _syncService;
  StreamSubscription<void>? _resyncSubscription;
  final _repoController = TextEditingController();
  final _tokenController = TextEditingController();
  final _cryptoPasswordController = TextEditingController();

  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isConfigured = false;
  String? _selectedKidId;
  TabController? _tabController;

  final Map<String, PagingState<int, dynamic>> _statesMap = {};

  @override
  void initState() {
    super.initState();
    _syncService = BiometricSyncService(widget.secureStorage);
    _loadSession();

    _resyncSubscription = BiometricSyncService.globalResyncTrigger.stream
        .listen((_) {
          if (mounted) {
            _loadSession();
          }
        });
  }

  Future<void> _loadSession() async {
    _isConfigured = await _syncService.loadCachedSession();
    if (_isConfigured) {
      _repoController.text = "Active Workspace Connected";
      if (_syncService.appData["kids"].isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        String? selectedKidId = prefs.getString(_keyLastSelectedKidId);
        if (selectedKidId != null &&
            _syncService.appData["kids"].any(
              (kid) => kid["id"] == selectedKidId,
            )) {
          _selectedKidId = selectedKidId;
        } else {
          _selectedKidId = _syncService.appData["kids"].first["id"];
        }
        _initializeTrackingStates();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resetAndRefreshAllViewports();
        });
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _initializeTrackingStates() {
    if (!mounted) return;

    final sheets = _syncService.schema?["sheets"] as List? ?? [];
    final int preservedIndex = _tabController?.index ?? 0;

    _tabController?.dispose();
    _tabController = TabController(
      length: sheets.length + 1,
      vsync: this,
      initialIndex: preservedIndex < (sheets.length + 1) ? preservedIndex : 0,
    );

    for (var sheet in sheets) {
      final String sid = sheet["id"].toString();
      _statesMap[sid] = PagingState(
        pages: [],
        keys: [],
        error: null,
        hasNextPage: true,
        isLoading: false,
      );
    }
  }

  void _fetchNextSlice(String sheetId) {
    if (_selectedKidId == null || _statesMap[sheetId] == null) return;

    final currentState = _statesMap[sheetId]!;
    final int startOffset =
        (currentState.keys != null && currentState.keys!.isNotEmpty)
        ? currentState.keys!.last
        : 0;

    final items = _syncService.getPagedAndReverseSortedData(
      kidId: _selectedKidId!,
      sheetId: sheetId,
      pageOffset: startOffset,
      pageSize: 15,
    );

    final bool hasNextPage = items.length == 15;
    final int nextOffset = startOffset + items.length;

    final updatedPages = [...?currentState.pages, items];
    final updatedKeys = [...?currentState.keys, nextOffset];

    setState(() {
      _statesMap[sheetId] = PagingState(
        pages: updatedPages,
        keys: updatedKeys,
        error: null,
        hasNextPage: hasNextPage,
        isLoading: false,
      );
    });
  }

  void _resetAndRefreshAllViewports() {
    if (!mounted) return;
    setState(() {
      _statesMap.forEach((key, value) {
        _statesMap[key] = PagingState(
          pages: [],
          keys: [],
          error: null,
          hasNextPage: true,
          isLoading: false,
        );
      });
    });
    final sheets = _syncService.schema?["sheets"] as List? ?? [];
    for (var sheet in sheets) {
      _fetchNextSlice(sheet["id"].toString());
    }
  }

  Future<void> _triggerConfigSync() async {
    if (_repoController.text.isEmpty ||
        _tokenController.text.isEmpty ||
        _cryptoPasswordController.text.isEmpty) {
      _showSnackBar("Please fill out all setup fields.");
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _syncService.saveServerConfig(
        repo: _repoController.text.trim(),
        token: _tokenController.text.trim(),
        password: _cryptoPasswordController.text.trim(),
      );
      await _syncService.syncFromGitHub();

      if (!mounted) return;

      if (_syncService.appData["kids"].isNotEmpty) {
        _selectedKidId = _syncService.appData["kids"].first["id"];
      }
      _initializeTrackingStates();
      setState(() => _isConfigured = true);
      _resetAndRefreshAllViewports();
    } catch (e) {
      if (mounted) _showSnackBar("Sync failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void dispose() {
    _resyncSubscription?.cancel();
    _repoController.dispose();
    _tokenController.dispose();
    _cryptoPasswordController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isConfigured) {
      return AthleteTrackerSetup(
        repoController: _repoController,
        tokenController: _tokenController,
        cryptoPasswordController: _cryptoPasswordController,
        onInitialize: _triggerConfigSync,
      );
    }

    final activeKid = _syncService.appData["kids"].firstWhere(
      (k) => k["id"] == _selectedKidId,
      orElse: () => null,
    );
    final sheets = _syncService.schema?["sheets"] as List? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Athlete Log Workspace"),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Commit to GitHub',
            onPressed: _isSyncing
                ? null
                : () async {
                    setState(() => _isSyncing = true);
                    try {
                      await _syncService.pushToGitHub();
                      _showSnackBar("Committed to Git!");
                    } catch (e) {
                      _showSnackBar("Error: $e");
                    } finally {
                      if (mounted) setState(() => _isSyncing = false);
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sync from GitHub',
            onPressed: _isSyncing
                ? null
                : () async {
                    setState(() => _isSyncing = true);
                    try {
                      await _syncService.syncFromGitHub();
                      _resetAndRefreshAllViewports();
                      _showSnackBar("Synced!");
                    } catch (e) {
                      _showSnackBar("Error: $e");
                    } finally {
                      if (mounted) setState(() => _isSyncing = false);
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnect',
            onPressed: () async {
              await _syncService.clearSavedSession();
              setState(() => _isConfigured = false);
            },
          ),
        ],
        bottom: _tabController != null
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  ...sheets.map<Tab>((s) => Tab(text: s["name"].toString())),
                  const Tab(text: "📊 Analytics Dashboard"),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          AthleteSelectorBar(
            kids: _syncService.appData["kids"],
            selectedKidId: _selectedKidId,
            activeKid: activeKid,
            onKidChanged: (v) {
              setState(() {
                _selectedKidId = v;
              });
              _resetAndRefreshAllViewports();
            },
            onKidAdded: () => BiometricDialogs.showKidForm(context, null, (
              name,
              age,
              gender,
            ) {
              final nid = DateTime.now().millisecondsSinceEpoch.toString();
              setState(() {
                _syncService.appData["kids"].add({
                  "id": nid,
                  "name": name,
                  "age": age,
                  "gender": gender,
                });
                _selectedKidId ??= nid;
              });
              _syncService.cacheLocally();
              _initializeTrackingStates();
              _resetAndRefreshAllViewports();
            }),
            onKidEdited: () => BiometricDialogs.showKidForm(
              context,
              activeKid,
              (name, age, gender) {
                setState(() {
                  activeKid!["name"] = name;
                  activeKid["age"] = age;
                  activeKid["gender"] = gender;
                });
                _syncService.cacheLocally();
                _resetAndRefreshAllViewports();
              },
            ),
            onKidDeleted: () {
              setState(() {
                _syncService.appData["kids"].removeWhere(
                  (k) => k["id"] == _selectedKidId,
                );
                _syncService.appData["biometrics"].removeWhere(
                  (b) => b["kid_id"] == _selectedKidId,
                );
                _selectedKidId = _syncService.appData["kids"].isNotEmpty
                    ? _syncService.appData["kids"].first["id"]
                    : null;
              });
              _syncService.cacheLocally();
              _initializeTrackingStates();
              _resetAndRefreshAllViewports();
            },
          ),
          Expanded(
            child: activeKid == null || _tabController == null
                ? const Center(
                    child: Text(
                      "Configure an athlete profile above to open logging grids.",
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      ...sheets.map<Widget>((sheet) {
                        final String sid = sheet["id"].toString();
                        return TrackerDataGrid(
                          sheet: sheet,
                          sheetId: sid,
                          columns: sheet["columns"],
                          activeKid: activeKid,
                          pagingState:
                              _statesMap[sid] ??
                              PagingState(
                                pages: [],
                                keys: [],
                                error: null,
                                hasNextPage: true,
                                isLoading: false,
                              ),
                          syncService: _syncService,
                          onFetchNextPage: () => _fetchNextSlice(sid),
                          onRowModified: _resetAndRefreshAllViewports,
                        );
                      }),

                      AthleteAnalyticsDashboard(
                        biometrics: _syncService.appData["biometrics"],
                        kidId: _selectedKidId!,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
