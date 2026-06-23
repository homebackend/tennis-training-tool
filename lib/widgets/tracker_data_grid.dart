/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter_common/tool.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../services/biometric_sync_service.dart';
import '../services/biometric_table_source.dart';
import 'biometric_dialogs.dart';

class TrackerDataGrid extends StatefulWidget {
  final Map sheet;
  final String sheetId;
  final List columns;
  final Map<String, dynamic> activeKid;
  final PagingState<int, dynamic> pagingState;
  final BiometricSyncService syncService;
  final VoidCallback onFetchNextPage;
  final VoidCallback onRowModified;

  const TrackerDataGrid({
    super.key,
    required this.sheet,
    required this.sheetId,
    required this.columns,
    required this.activeKid,
    required this.pagingState,
    required this.syncService,
    required this.onFetchNextPage,
    required this.onRowModified,
  });

  @override
  State<TrackerDataGrid> createState() => _TrackerDataGridState();
}

class _TrackerDataGridState extends State<TrackerDataGrid> {
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Widget _logHeader(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    physics: const BouncingScrollPhysics(),
    child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Logs for ${widget.activeKid['name']} (Newest First)",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.blueGrey,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () => BiometricDialogs.showMetricsRowForm(
              context,
              widget.sheet,
              null,
              (newData) {
                newData["kid_id"] = widget.activeKid["id"];
                newData["sheet_id"] = widget.sheetId;
                newData["entry_id"] = DateTime.now().millisecondsSinceEpoch
                    .toString();
                for (var col in widget.columns) {
                  if (col["type"] == "computed") {
                    newData[col["id"]] = widget.syncService.computeFormulaValue(
                      col["formula"],
                      newData,
                    );
                  }
                }
                widget.syncService.appData["biometrics"].add(newData);
                widget.syncService.cacheLocally();
                widget.onRowModified();
              },
            ),
            icon: const Icon(Icons.add),
            label: const Text("Log New Entry"),
          ),
        ],
      ),
    ),
  );

  Widget _contents(List<dynamic> allItems) {
    final tableSource = BiometricTableSource(
      allRows: allItems,
      columns: widget.columns,
      context: context,
      syncService: widget.syncService,
      sheet: widget.sheet,
      sheetId: widget.sheetId,
      activeKid: widget.activeKid,
      onRowModified: widget.onRowModified,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: PaginatedDataTable(
        horizontalMargin: 24,
        header: const Text(
          "Logged Metrics",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        rowsPerPage: 10,
        columns: [
          ...widget.columns.map(
            (c) => DataColumn(
              label: Text(
                c["name"],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const DataColumn(
            label: Text(
              "Actions",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
        source: tableSource,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allItems =
        widget.pagingState.pages?.expand((page) => page).toList() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _logHeader(context),
        Expanded(
          child: allItems.isEmpty
              ? const Center(
                  child: Text("No records logged in this sheet yet."),
                )
              : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: true),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      scrollbarTheme: const ScrollbarThemeData(
                        thumbVisibility: WidgetStatePropertyAll(true),
                        trackVisibility: WidgetStatePropertyAll(true),
                      ),
                    ),
                    child: isDesktopPlatform()
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              final computedMinimumWidth =
                                  (widget.columns.length * 140.0) + 100.0;

                              final tableTargetWidth =
                                  constraints.maxWidth > computedMinimumWidth
                                  ? constraints.maxWidth
                                  : computedMinimumWidth;

                              return Scrollbar(
                                controller: _horizontalScrollController,
                                thumbVisibility: true,
                                trackVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _horizontalScrollController,
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: tableTargetWidth,
                                    child: _contents(allItems),
                                  ),
                                ),
                              );
                            },
                          )
                        : _contents(allItems),
                  ),
                ),
        ),
      ],
    );
  }
}
