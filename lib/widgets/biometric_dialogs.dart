/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

class BiometricDialogs {
  static void showKidForm(
    BuildContext context,
    Map<String, dynamic>? existingKid,
    Function(String, int, String) onSave,
  ) {
    final nameCtrl = TextEditingController(text: existingKid?["name"]);
    final ageCtrl = TextEditingController(
      text: existingKid?["age"]?.toString(),
    );
    String gender = existingKid?["gender"] ?? "male";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existingKid == null
                ? "Register Athlete Profile"
                : "Modify Profile Info",
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Child Name"),
              ),
              TextField(
                controller: ageCtrl,
                decoration: const InputDecoration(labelText: "Age"),
                keyboardType: TextInputType.number,
              ),
              DropdownButton<String>(
                value: gender,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: "male", child: Text("Male")),
                  DropdownMenuItem(value: "female", child: Text("Female")),
                ],
                onChanged: (v) => setDialogState(() => gender = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isEmpty ||
                    int.tryParse(ageCtrl.text) == null) {
                  return;
                }
                onSave(nameCtrl.text.trim(), int.parse(ageCtrl.text), gender);
                Navigator.pop(ctx);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  static void showMetricsRowForm(
    BuildContext context,
    Map? activeSheetSchema,
    Map<String, dynamic>? existingRow,
    Function(Map<String, dynamic>) onSave,
  ) {
    if (activeSheetSchema == null) return;
    final Map<String, TextEditingController> controllers = {};
    final Map<String, String> booleanValues = {};
    final formKey = GlobalKey<FormState>();

    final columns = activeSheetSchema["columns"];

    for (var col in columns) {
      if (col["type"] == "computed") continue;

      if (col["type"] == "boolean") {
        booleanValues[col["id"]] = existingRow?[col["id"]]?.toString() ?? "Yes";
      } else {
        controllers[col["id"]] = TextEditingController(
          text:
              existingRow?[col["id"]]?.toString() ??
              (col["id"] == "Date" || col["id"] == "WeekStart"
                  ? DateTime.now().toString().split(' ').first
                  : ""),
        );
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existingRow == null ? "Log Row Entry" : "Modify Record"),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: ListView(
              shrinkWrap: true,
              children: columns.map<Widget>((col) {
                if (col["type"] == "computed") return const SizedBox.shrink();

                if (col["type"] == "boolean") {
                  return StatefulBuilder(
                    builder: (context, setDropdownState) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: DropdownButtonFormField<String>(
                        initialValue: booleanValues[col["id"]],
                        decoration: InputDecoration(
                          labelText: col["name"],
                          border: const OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "Yes",
                            child: Text("Yes / Pass"),
                          ),
                          DropdownMenuItem(
                            value: "No",
                            child: Text("No / Fail"),
                          ),
                        ],
                        onChanged: (v) => setDropdownState(
                          () => booleanValues[col["id"]] = v!,
                        ),
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: TextFormField(
                    controller: controllers[col["id"]],
                    decoration: InputDecoration(
                      labelText: col["name"],
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType:
                        col["type"] == "integer" || col["type"] == "numeric"
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.datetime,
                    validator: (value) {
                      if ((col["optional"] ?? false) && col["type"] == "text") {
                        return null;
                      }

                      if (value == null || value.trim().isEmpty) {
                        return "Field cannot be empty.";
                      }
                      if (col["type"] == "integer") {
                        final parsedInt = int.tryParse(value.trim());
                        if (parsedInt == null) {
                          return "Must be a valid integer.";
                        }
                        if (col["min"] != null && parsedInt < col["min"]) {
                          return "Min allowed value is ${col['min']}.";
                        }
                        if (col["max"] != null && parsedInt > col["max"]) {
                          return "Max allowed value is ${col['max']}.";
                        }
                      }
                      if (col["type"] == "numeric" &&
                          double.tryParse(value.trim()) == null) {
                        return "Must be a valid number.";
                      }
                      return null;
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final Map<String, dynamic> rowData = {};
                for (var col in columns) {
                  if (col["type"] == "computed") continue;

                  if (col["type"] == "boolean") {
                    rowData[col["id"]] = booleanValues[col["id"]];
                  } else {
                    String valStr = controllers[col["id"]]!.text.trim();
                    if (col["type"] == "integer") {
                      rowData[col["id"]] = int.parse(valStr);
                    } else if (col["type"] == "numeric") {
                      rowData[col["id"]] = double.parse(valStr);
                    } else {
                      rowData[col["id"]] = valStr;
                    }
                  }
                }
                onSave(rowData);
                Navigator.pop(ctx);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}
