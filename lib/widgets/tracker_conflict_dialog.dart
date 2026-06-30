/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

import '../services/tracker_sync_service.dart';

class TrackerConflictResolutionDialog extends StatefulWidget {
  final SheetConflict conflict;

  const TrackerConflictResolutionDialog(this.conflict, {super.key});

  @override
  State<TrackerConflictResolutionDialog> createState() =>
      _TrackerConflictResolutionDialogState();
}

class _TrackerConflictResolutionDialogState
    extends State<TrackerConflictResolutionDialog> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    if (widget.conflict is SheetRowEditedConflict) {
      for (var conflict
          in (widget.conflict as SheetRowEditedConflict).conflicts.values) {
        _controllers[conflict.columnName] = TextEditingController(
          text: conflict.localValue,
        );
      }
    }
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Widget> _showRowAddedDeleted() => [
    const Padding(
      padding: EdgeInsets.only(bottom: 12.0),
      child: Text(
        "Review cell values below",
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontStyle: FontStyle.italic,
        ),
      ),
    ),
    DataTable(
      columnSpacing: 16,
      horizontalMargin: 0,
      columns: const [
        DataColumn(
          label: Text("Field", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        DataColumn(
          label: Text(
            "Value",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ),
      ],
      rows: widget.conflict.row.entries
          .map(
            (entry) => DataRow(
              cells: [
                DataCell(Text(entry.key, style: const TextStyle(fontSize: 12))),
                DataCell(
                  Text(
                    entry.value.toString(),
                    style: const TextStyle(color: Colors.blue, fontSize: 13),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    ),
  ];

  DataRow _getDataRow(
    SheetRowEditedConflict conflict,
    String field,
    String value,
  ) => DataRow(
    cells: [
      DataCell(Text(field, style: const TextStyle(fontSize: 12))),
      if (conflict.conflicts.containsKey(field)) ...[
        DataCell(
          InkWell(
            onTap: () => setState(
              () => _controllers[field]!.text =
                  conflict.conflicts[field]!.localValue,
            ),
            child: Text(
              conflict.conflicts[field]!.localValue,
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        DataCell(
          InkWell(
            onTap: () => setState(
              () => _controllers[field]!.text =
                  conflict.conflicts[field]!.incomingValue,
            ),
            child: Text(
              conflict.conflicts[field]!.incomingValue,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        DataCell(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: TextField(
              controller: _controllers[field],
              maxLines: null,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
      if (!conflict.conflicts.containsKey(field)) ...[
        DataCell(
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
          ),
        ),
        DataCell(
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
          ),
        ),
        DataCell(
          Text(
            value,
            style: const TextStyle(color: Colors.green, fontSize: 13),
          ),
        ),
      ],
    ],
  );

  List<Widget> _showRowEdited(SheetRowEditedConflict conflict) => [
    const Padding(
      padding: EdgeInsets.only(bottom: 12.0),
      child: Text(
        "Review cell values below. Edit values in 'Output Choice' column if required.",
        softWrap: true,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontStyle: FontStyle.italic,
        ),
      ),
    ),
    DataTable(
      columnSpacing: 16,
      horizontalMargin: 0,
      columns: const [
        DataColumn(
          label: Text("Field", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        DataColumn(
          label: Text(
            "Your Version",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        ),
        DataColumn(
          label: Text(
            "Incoming Version",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ),
        DataColumn(
          label: Text(
            "Output Choice",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ),
      ],
      rows: [
        ...conflict.row.entries.map(
          (entry) => _getDataRow(conflict, entry.key, entry.value.toString()),
        ),
        ...conflict.conflicts.keys
            .where((key) => !conflict.row.containsKey(key))
            .map((field) => _getDataRow(conflict, field, '')),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.g_mobiledata, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Sync Conflict: for ${widget.conflict.type} with ${widget.conflict.idKey} = ${widget.conflict.row[widget.conflict.idKey]}",
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        physics: BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.conflict is SheetRowEditedConflict
              ? _showRowEdited(widget.conflict as SheetRowEditedConflict)
              : _showRowAddedDeleted(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel Commit'),
        ),
        if (widget.conflict is SheetRowEditedConflict)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade800,
            ),
            onPressed: () {
              SheetRowEditedConflict c =
                  widget.conflict as SheetRowEditedConflict;

              for (var key in c.conflicts.keys) {
                final controllerValue = _controllers[key]!.text.trim();

                final cellConflict = c.conflicts[key];
                if (controllerValue.isEmpty &&
                    (!cellConflict!.localValuePresent ||
                        !cellConflict.incomingValuePresent)) {
                  c.row.remove(key);
                } else {
                  c.row[key] = controllerValue;
                }
              }
              Navigator.of(context).pop(true);
            },
            child: const Text(
              "Save & Next Row",
              style: TextStyle(color: Colors.white),
            ),
          ),
        if (widget.conflict is SheetRowAddedConflict ||
            widget.conflict is SheetRowDeletedConflict) ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
            ),
            onPressed: () {
              if (widget.conflict is SheetRowAddedConflict) {
                (widget.conflict as SheetRowAddedConflict).remove();
              } else {
                (widget.conflict as SheetRowDeletedConflict).remove();
              }

              Navigator.of(context).pop(true);
            },
            child: const Text(
              "Remove this Item",
              style: TextStyle(color: Colors.white),
            ),
          ),
          SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade800,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              "Keep this Item",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ],
    );
  }
}
