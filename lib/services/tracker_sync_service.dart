/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

class CellConflict {
  final String columnName;
  final String localValue;
  final String incomingValue;

  CellConflict({
    required this.columnName,
    required this.localValue,
    required this.incomingValue,
  });
}

sealed class SheetConflict {
  final Map<String, dynamic> row;
  final String type;
  final String idKey;

  SheetConflict(this.row, this.type, this.idKey);
}

class SheetRowEditedConflict extends SheetConflict {
  final Map<String, CellConflict> conflicts = {};

  SheetRowEditedConflict(super.row, super.type, super.idKey);

  void addCellConflict(CellConflict cellConflict) =>
      conflicts[cellConflict.columnName] = cellConflict;
}

class SheetRowAddedConflict extends SheetConflict {
  void Function() remove;
  SheetRowAddedConflict(super.row, super.type, super.idKey, this.remove);
}

class SheetRowDeletedConflict extends SheetConflict {
  void Function() remove;
  SheetRowDeletedConflict(super.row, super.type, super.idKey, this.remove);
}
