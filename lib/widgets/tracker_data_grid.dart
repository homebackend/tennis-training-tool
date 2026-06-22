/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../services/biometric_sync_service.dart';
import 'biometric_dialogs.dart';

class TrackerDataGrid extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Logs for ${activeKid['name']} (Newest First)",
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => BiometricDialogs.showMetricsRowForm(
                  context,
                  sheet,
                  null,
                  (newData) {
                    newData["kid_id"] = activeKid["id"];
                    newData["sheet_id"] = sheetId;
                    newData["entry_id"] = DateTime.now().millisecondsSinceEpoch
                        .toString();
                    for (var col in columns) {
                      if (col["type"] == "computed") {
                        newData[col["id"]] = syncService.computeFormulaValue(
                          col["formula"],
                          newData,
                        );
                      }
                    }
                    syncService.appData["biometrics"].add(newData);
                    syncService.cacheLocally();
                    onRowModified();
                  },
                ),
                icon: const Icon(Icons.add),
                label: const Text("Log New Entry"),
              ),
            ],
          ),
        ),
        Container(
          color: Colors.grey.shade200,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            children: [
              ...columns.map(
                (c) => Expanded(
                  child: Text(
                    c["name"],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  "Actions",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PagedListView<int, dynamic>(
            state: pagingState,
            fetchNextPage: onFetchNextPage,
            builderDelegate: PagedChildBuilderDelegate<dynamic>(
              noItemsFoundIndicatorBuilder: (context) => const Center(
                child: Text("No records logged in this sheet yet."),
              ),
              itemBuilder: (context, row, index) {
                final allItems =
                    pagingState.pages?.expand((page) => page).toList() ?? [];
                if (index >= allItems.length) return const SizedBox.shrink();
                final currentRow = allItems[index];

                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      ...columns.map<Widget>((col) {
                        var value = currentRow[col["id"]];
                        if (col["type"] == "computed") {
                          value = syncService.computeFormulaValue(
                            col["formula"],
                            currentRow,
                          );
                        }

                        if (col["id"] == "Notes" && value != null) {
                          final String noteText = value.toString();
                          final bool isLong = noteText.length > 10;

                          return Expanded(
                            child: Tooltip(
                              message: noteText,
                              preferBelow: false,
                              child: Text(
                                isLong
                                    ? "${noteText.substring(0, 10)}..."
                                    : noteText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          );
                        }

                        Color txtCol = Colors.black87;
                        String ruleLabel = "";
                        if (col["rules"] != null && value is num) {
                          final eval = syncService.evaluateRule(
                            sheetId,
                            col["id"],
                            value.toDouble(),
                            activeKid["gender"],
                          );
                          txtCol = eval["color"];
                          ruleLabel = eval["label"] != ""
                              ? " (${eval['label']})"
                              : "";
                        }

                        final textDisplay = value is double
                            ? value.toStringAsFixed(1)
                            : (value?.toString() ?? "");
                        return Expanded(
                          child: Text(
                            "$textDisplay$ruleLabel",
                            style: TextStyle(
                              color: txtCol,
                              fontSize: 12,
                              fontWeight: ruleLabel.isNotEmpty
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      }),
                      SizedBox(
                        width: 80,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                  size: 16,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () =>
                                    BiometricDialogs.showMetricsRowForm(
                                      context,
                                      sheet,
                                      currentRow,
                                      (updated) {
                                        currentRow.addAll(updated);
                                        for (var col in columns) {
                                          if (col["type"] == "computed") {
                                            currentRow[col["id"]] = syncService
                                                .computeFormulaValue(
                                                  col["formula"],
                                                  currentRow,
                                                );
                                          }
                                        }
                                        syncService.cacheLocally();
                                        onRowModified();
                                      },
                                    ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 16,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  syncService.appData["biometrics"].removeWhere(
                                    (b) =>
                                        b["entry_id"] == currentRow["entry_id"],
                                  );
                                  syncService.cacheLocally();
                                  onRowModified();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
