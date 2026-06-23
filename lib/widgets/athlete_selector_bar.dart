/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

class AthleteSelectorBar extends StatelessWidget {
  final List<dynamic> kids;
  final String? selectedKidId;
  final Map<String, dynamic>? activeKid;
  final ValueChanged<String?> onKidChanged;
  final VoidCallback onKidAdded;
  final VoidCallback onKidEdited;
  final VoidCallback onKidDeleted;

  const AthleteSelectorBar({
    super.key,
    required this.kids,
    required this.selectedKidId,
    required this.activeKid,
    required this.onKidChanged,
    required this.onKidAdded,
    required this.onKidEdited,
    required this.onKidDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.blue.shade50,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            const Text(
              "Active Child:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 250,
              child: kids.isEmpty
                  ? const Text(
                      "⚠️ Add a kid profile to begin track logs",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : DropdownButton<String>(
                      value: selectedKidId,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: kids.map<DropdownMenuItem<String>>((k) {
                        return DropdownMenuItem(
                          value: k["id"].toString(),
                          child: Text(
                            "${k['name']} (${k['gender']}, Age: ${k['age']})",
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: onKidChanged,
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.green),
              onPressed: onKidAdded,
            ),
            if (activeKid != null) ...[
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue),
                onPressed: onKidEdited,
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmProfileErasure(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmProfileErasure(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ Critical Deletion Warning"),
        content: const Text(
          "Deleting this kid profile will wipe all historical data associated with them. Proceed?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              onKidDeleted();
              Navigator.pop(ctx);
            },
            child: const Text("Wipe Child Data"),
          ),
        ],
      ),
    );
  }
}
