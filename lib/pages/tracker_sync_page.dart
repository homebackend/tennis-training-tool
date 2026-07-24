/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_common/mixin/main_config_manager.dart';
import 'package:flutter_common/mixin/page_common.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tracker_sync_service.dart';
import '../tool.dart';
import '../widgets/athlete_analytics_dashboard.dart';
import '../widgets/biometric_dialogs.dart';
import '../widgets/athlete_selector_bar.dart';
import '../widgets/tracker_conflict_dialog.dart';
import '../widgets/tracker_data_grid.dart';

class TrackerSyncPage extends StatefulWidget {
  final FlutterSecureStorage secureStorage;
  final SharedPreferences sharedPreferences;
  final MainConfigManager configManager;
  const TrackerSyncPage(
    this.secureStorage,
    this.sharedPreferences,
    this.configManager, {
    super.key,
  });

  @override
  State<TrackerSyncPage> createState() => _TrackerSyncPageState();
}

class _TrackerSyncPageState extends State<TrackerSyncPage>
    with PageCommon, TickerProviderStateMixin {
  static final String _keyLastSelectedKidId = 'last_selected_kid_id';

  late final TrackerSyncService _syncService;
  StreamSubscription<void>? _resyncSubscription;

  bool _isLoading = true;
  bool _isSyncing = false;
  bool _localDataModified = false;
  String? _selectedKidId;
  TabController? _tabController;

  final Map<String, PagingState<int, dynamic>> _statesMap = {};

  @override
  void initState() {
    super.initState();

    _init();
    _resyncSubscription = TrackerSyncService.globalResyncTrigger.stream.listen((
      _,
    ) {
      if (mounted) {
        _loadSession();
      }
    });
  }

  Future<void> _init() async {
    _syncService = TrackerSyncService(
      widget.secureStorage,
      widget.sharedPreferences,
      () => setState(() => _isSyncing = true),
      () => setState(() => _isSyncing = false),
      () => setState(() => _isSyncing = false),
      (self) async {
        if (mounted) _resetAndRefreshAllViewports();
      },
    );
    await _loadSession();
  }

  Future<void> _loadSession() async {
    await _syncService.initialize();
    _localDataModified = await _syncService.hasSyncDataModified();
    if (_syncService.appData["kids"].isNotEmpty) {
      String? selectedKidId = widget.sharedPreferences.getString(
        _keyLastSelectedKidId,
      );
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

  void _showSnackBar(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void dispose() {
    _syncService.disposeSyncer();
    _resyncSubscription?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final activeKid = _selectedKidId != null
        ? _syncService.appData["kids"].firstWhere(
            (k) => k["id"] == _selectedKidId,
            orElse: null,
          )
        : null;
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
          if (_localDataModified)
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'Commit to GitHub',
              onPressed: _isSyncing
                  ? null
                  : () async {
                      try {
                        await runSequentialSyncPipeline();
                      } catch (e) {
                        _showSnackBar("Error: $e");
                      }
                    },
            ),
          if (!_localDataModified)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Sync from GitHub',
              onPressed: _isSyncing
                  ? null
                  : () async {
                      try {
                        await _syncService.syncData();
                        _resetAndRefreshAllViewports();
                        _showSnackBar("Synced!");
                      } catch (e) {
                        _showSnackBar("Error: $e");
                      }
                    },
            ),
          ...getAppBarCommonActions(widget.configManager),
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
            onKidChanged: (v) async {
              if (v != null) {
                await widget.sharedPreferences.setString(
                  _keyLastSelectedKidId,
                  v,
                );
              }
              setState(() {
                _selectedKidId = v;
              });
              _resetAndRefreshAllViewports();
            },
            onKidAdded: () => BiometricDialogs.showKidForm(context, null, (
              name,
              age,
              gender,
            ) async {
              await _syncService.setSyncDataModified(true);
              final nid = getNewUuid();
              setState(() {
                _localDataModified = true;
                _syncService.appData["kids"].add({
                  "id": nid,
                  "name": name,
                  "age": age,
                  "gender": gender,
                });
                _selectedKidId ??= nid;
              });
              _syncService.cacheAppDataLocally();
              _initializeTrackingStates();
              _resetAndRefreshAllViewports();
            }),
            onKidEdited: () => BiometricDialogs.showKidForm(
              context,
              activeKid,
              (name, age, gender) async {
                await _syncService.setSyncDataModified(true);
                setState(() {
                  _localDataModified = true;
                  activeKid!["name"] = name;
                  activeKid["age"] = age;
                  activeKid["gender"] = gender;
                });
                _syncService.cacheAppDataLocally();
                _resetAndRefreshAllViewports();
              },
            ),
            onKidDeleted: () async {
              await _syncService.setSyncDataModified(true);
              setState(() {
                _localDataModified = true;
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
              _syncService.cacheAppDataLocally();
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
                          onRowModified: () {
                            _syncService.setSyncDataModified(true);
                            setState(() => _localDataModified = true);
                            _resetAndRefreshAllViewports();
                          },
                        );
                      }),
                      AthleteAnalyticsDashboard(
                        biometrics: _syncService.appData["biometrics"],
                        kidId: _selectedKidId!,
                        kids: _syncService.appData["kids"],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> runSequentialSyncPipeline({
    int attempt = 0,
    String? retryServerFileSha,
  }) async {
    try {
      await _syncService.pushToGitHubWithAutoMerge(
        retryServerFileSha: retryServerFileSha,
      );
      await _syncService.setSyncDataModified(false);
      setState(() => _localDataModified = false);
      _resetAndRefreshAllViewports();
      _showSnackBar("Saved tracker data!");
    } catch (e) {
      if (e is ConcurrentModificationException && attempt <= 3) {
        if (e.conflicts.isEmpty) {
          _showSnackBar("Re-trying save (Attempt ${attempt + 1}/3)...");
        } else {
          _showSnackBar(
            "Another user has modified tracker data. Please resolve conflicts ...",
          );

          for (final conflict in e.conflicts) {
            if (context.mounted) {
              final ok = await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => TrackerConflictResolutionDialog(conflict),
              );

              if (ok != true) {
                _showSnackBar('Saving data cancelled!');
                return;
              }
            }

            _showSnackBar(
              "Thanks for Resolving. Re-trying save (Attempt ${attempt + 1}/3)...",
            );
          }
        }
        await runSequentialSyncPipeline(
          attempt: attempt + 1,
          retryServerFileSha: e.serverFileSha,
        );
      } else {
        rethrow;
      }
    }
  }

  @override
  FlutterSecureStorage get secureStorage => widget.secureStorage;
}
