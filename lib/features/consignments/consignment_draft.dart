import 'consignment_models.dart';

/// Canonical draft-line identity for consignment create / add-items.
///
/// Identity = productId + variation (size/color/extra).
/// Never uses name, empty barcode, empty code, or list index.
class ConsignmentDraftLineIdentity {
  const ConsignmentDraftLineIdentity({
    required this.productId,
    this.size = '',
    this.color = '',
    this.extra = '',
  });

  final String productId;
  final String size;
  final String color;
  final String extra;

  factory ConsignmentDraftLineIdentity.fromLine(ConsignmentDraftLine line) {
    return ConsignmentDraftLineIdentity(
      productId: line.productId,
      size: line.variationKey.size,
      color: line.variationKey.color,
      extra: line.variationKey.extra,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConsignmentDraftLineIdentity &&
        other.productId == productId &&
        other.size == size &&
        other.color == color &&
        other.extra == extra;
  }

  @override
  int get hashCode => Object.hash(productId, size, color, extra);

  @override
  String toString() => '$productId|$size|$color|$extra';
}

/// Pure in-memory draft mutations. No stock / Firestore writes.
class ConsignmentDraftMutator {
  /// Same-product policy: increment qty of existing matching line.
  static const duplicatePolicy = 'INCREMENT_QTY';

  static int indexOfIdentity(
    List<ConsignmentDraftLine> lines,
    ConsignmentDraftLineIdentity identity,
  ) {
    for (var i = 0; i < lines.length; i++) {
      if (ConsignmentDraftLineIdentity.fromLine(lines[i]) == identity) {
        return i;
      }
    }
    return -1;
  }

  /// Appends [next] or merges qty when canonical line identity already exists.
  /// Never replaces the list; never drops unrelated lines.
  static void addOrMerge(
    List<ConsignmentDraftLine> lines,
    ConsignmentDraftLine next,
  ) {
    final id = ConsignmentDraftLineIdentity.fromLine(next);
    if (id.productId.trim().isEmpty) {
      throw ArgumentError('productId is required for consignment draft lines');
    }
    final i = indexOfIdentity(lines, id);
    if (i >= 0) {
      final existing = lines[i];
      final add = next.qtySent < 1 ? 1 : next.qtySent;
      existing.qtySent = existing.qtySent + add;
      return;
    }
    lines.add(next);
  }
}
