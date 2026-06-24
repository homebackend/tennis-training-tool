/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

import '../services/tracker_sync_service.dart';

class ConflictResolutionDialog extends StatefulWidget {
  final SheetConflict conflict;
  final void Function() onResolved;

  const ConflictResolutionDialog(this.conflict, this.onResolved, {super.key});

  @override
  State<ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<ConflictResolutionDialog> {
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
                    entry.value,
                    style: const TextStyle(color: Colors.blue, fontSize: 13),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    ),
  ];

  List<Widget> _showRowEdited(SheetRowEditedConflict conflict) => [
    const Padding(
      padding: EdgeInsets.only(bottom: 12.0),
      child: Text(
        "Review cell values below. Column 3 can be edited before saving.",
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
      rows: widget.conflict.row.entries
          .map(
            (entry) => DataRow(
              cells: [
                DataCell(Text(entry.key, style: const TextStyle(fontSize: 12))),
                if (conflict.conflicts.containsKey(entry.key)) ...[
                  DataCell(
                    Text(
                      conflict.conflicts[entry.key]!.localValue,
                      style: const TextStyle(color: Colors.blue, fontSize: 13),
                    ),
                  ),
                  DataCell(
                    Text(
                      conflict.conflicts[entry.key]!.incomingValue,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                  DataCell(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: TextField(
                        controller: _controllers[entry.key],
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
                if (!conflict.conflicts.containsKey(entry.key)) ...[
                  DataCell(
                    Text(
                      entry.value,
                      style: const TextStyle(color: Colors.blue, fontSize: 13),
                    ),
                  ),
                  DataCell(
                    Text(
                      entry.value,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                  DataCell(
                    Text(
                      entry.value,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          )
          .toList(),
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
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 700,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.conflict is SheetRowEditedConflict
                  ? _showRowEdited(widget.conflict as SheetRowEditedConflict)
                  : _showRowAddedDeleted(),
            ),
          ),
        ),
      ),
      actions: [
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
                c.row[key] = controllerValue;
              }
              widget.onResolved();
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

              widget.onResolved();
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
            onPressed: widget.onResolved,
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
