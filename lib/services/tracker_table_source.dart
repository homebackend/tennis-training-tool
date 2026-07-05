/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

import '../widgets/biometric_dialogs.dart';
import 'tracker_sync_service.dart';

class TrackerTableSource extends DataTableSource {
  final List<dynamic> allRows;
  final List<dynamic> columns;
  final BuildContext context;
  final TrackerSyncService syncService;
  final dynamic sheet;
  final dynamic sheetId;
  final dynamic activeKid;
  final VoidCallback onRowModified;

  TrackerTableSource({
    required this.allRows,
    required this.columns,
    required this.context,
    required this.syncService,
    required this.sheet,
    required this.sheetId,
    required this.activeKid,
    required this.onRowModified,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= allRows.length) return null;
    final currentRow = allRows[index];

    final cells = columns.map<DataCell>((col) {
      var value = currentRow[col["id"]];
      if (col["type"] == "computed") {
        value = syncService.computeFormulaValue(col["formula"], currentRow);
      }

      if (col["id"] == "Notes" && value != null) {
        final String noteText = value.toString();
        final bool isLong = noteText.length > 10;

        return DataCell(
          Tooltip(
            message: noteText,
            preferBelow: false,
            child: Text(
              isLong ? "${noteText.substring(0, 10)}..." : noteText,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
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
        ruleLabel = eval["label"] != "" ? " (${eval['label']})" : "";
      }

      final textDisplay = value is double
          ? value.toStringAsFixed(1)
          : (value?.toString() ?? "");

      return DataCell(
        Text(
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
    }).toList();

    cells.add(
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => BiometricDialogs.showMetricsRowForm(
                context,
                sheet,
                activeKid,
                currentRow,
                (updated) async {
                  currentRow.addAll(updated);
                  for (var col in columns) {
                    if (col["type"] == "computed") {
                      currentRow[col["id"]] = syncService.computeFormulaValue(
                        col["formula"],
                        currentRow,
                      );
                    }
                  }
                  await syncService.cacheAppDataLocally();
                  onRowModified();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () async {
                syncService.appData["biometrics"].removeWhere(
                  (b) => b["entry_id"] == currentRow["entry_id"],
                );
                await syncService.cacheAppDataLocally();
                onRowModified();
              },
            ),
          ],
        ),
      ),
    );

    return DataRow(cells: cells);
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => allRows.length;

  @override
  int get selectedRowCount => 0;
}
