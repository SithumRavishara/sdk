// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/nullability/decorated_type.dart'
    as analyzer;
import 'package:analysis_server/src/nullability/expression_checks.dart'
    as analyzer;
import 'package:analysis_server/src/nullability/transitional_api.dart'
    as analyzer;
import 'package:analysis_server/src/protocol_server.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:meta/meta.dart';

export 'package:analysis_server/src/nullability/transitional_api.dart'
    show NamedNoDefaultParameterHeuristic, NullabilityMigrationAssumptions;

/// Kinds of fixes that might be performed by nullability migration.
class NullabilityFixKind {
  /// An import needs to be added.
  static const addImport =
      const NullabilityFixKind._(appliedMessage: 'Add an import');

  /// A formal parameter needs to have a required annotation added.
  static const addRequired =
      const NullabilityFixKind._(appliedMessage: 'Add a required annotation');

  /// An expression's value needs to be null-checked.
  static const checkExpression = const NullabilityFixKind._(
    appliedMessage: 'Added a null check to an expression',
  );

  /// An explicit type mentioned in the source program needs to be made
  /// nullable.
  static const makeTypeNullable = const NullabilityFixKind._(
    appliedMessage: 'Changed a type to be nullable',
  );

  /// An if-test or conditional expression needs to have its "then" branch
  /// discarded.
  static const discardThen = const NullabilityFixKind._(
    appliedMessage: 'Discarded an unreachable conditional then branch',
  );

  /// An if-test or conditional expression needs to have its "else" branch
  /// discarded.
  static const discardElse = const NullabilityFixKind._(
    appliedMessage: 'Discarded an unreachable conditional else branch',
  );

  /// A message used by dartfix to indicate a fix has been applied.
  final String appliedMessage;

  const NullabilityFixKind._({@required this.appliedMessage});
}

/// Provisional API for DartFix to perform nullability migration.
///
/// Usage: pass each input source file to [prepareInput].  Then pass each input
/// source file to [processInput].  Then call [finish] to obtain the
/// modifications that need to be made to each source file.
///
/// TODO(paulberry): figure out whether this API is what we want, and figure out
/// what file/folder it belongs in.
class NullabilityMigration {
  final analyzer.NullabilityMigration _analyzerMigration;
  final NullabilityMigrationListener listener;

  /// Prepares to perform nullability migration.
  ///
  /// If [permissive] is `true`, exception handling logic will try to proceed
  /// as far as possible even though the migration algorithm is not yet
  /// complete.  TODO(paulberry): remove this mode once the migration algorithm
  /// is fully implemented.
  NullabilityMigration(this.listener,
      {bool permissive: false,
      analyzer.NullabilityMigrationAssumptions assumptions:
          const analyzer.NullabilityMigrationAssumptions()})
      : _analyzerMigration = analyzer.NullabilityMigration(
            permissive: permissive, assumptions: assumptions);

  void finish() {
    for (var entry in _analyzerMigration.finish().entries) {
      var source = entry.key;
      for (var potentialModification in entry.value) {
        var fix = _SingleNullabilityFix(source, potentialModification);
        listener.addFix(fix);
        for (var edit in potentialModification.modifications) {
          listener.addEdit(fix, edit);
        }
      }
    }
  }

  void prepareInput(ResolvedUnitResult result) {
    _analyzerMigration.prepareInput(result.unit);
  }

  void processInput(ResolvedUnitResult result) {
    _analyzerMigration.processInput(result.unit, result.typeProvider);
  }
}

/// [NullabilityMigrationListener] is used by [NullabilityMigration]
/// to communicate source changes or "fixes" to the client.
abstract class NullabilityMigrationListener {
  /// [addEdit] is called once for each source edit, in the order in which they
  /// appear in the source file.
  void addEdit(SingleNullabilityFix fix, SourceEdit edit);

  /// [addFix] is called once for each source change.
  void addFix(SingleNullabilityFix fix);
}

/// Representation of a single conceptual change made by the nullability
/// migration algorithm.  This change might require multiple source edits to
/// achieve.
abstract class SingleNullabilityFix {
  /// What kind of fix this is.
  NullabilityFixKind get kind;

  /// Location of the change, for reporting to the user.
  Location get location;

  /// File to change.
  Source get source;
}

/// Implementation of [SingleNullabilityFix] used internally by
/// [NullabilityMigration].
class _SingleNullabilityFix extends SingleNullabilityFix {
  @override
  final Source source;

  @override
  final NullabilityFixKind kind;

  factory _SingleNullabilityFix(
      Source source, analyzer.PotentialModification potentialModification) {
    // TODO(paulberry): once everything is migrated into the analysis server,
    // the migration engine can just create SingleNullabilityFix objects
    // directly and set their kind appropriately; we won't need to translate the
    // kinds using a bunch of `is` checks.
    NullabilityFixKind kind;
    if (potentialModification is analyzer.ExpressionChecks) {
      kind = NullabilityFixKind.checkExpression;
    } else if (potentialModification is analyzer.DecoratedTypeAnnotation) {
      kind = NullabilityFixKind.makeTypeNullable;
    } else if (potentialModification is analyzer.ConditionalModification) {
      kind = potentialModification.discard.keepFalse.value
          ? NullabilityFixKind.discardThen
          : NullabilityFixKind.discardElse;
    } else if (potentialModification is analyzer.PotentiallyAddImport) {
      kind = NullabilityFixKind.addImport;
    } else if (potentialModification is analyzer.PotentiallyAddRequired) {
      kind = NullabilityFixKind.addRequired;
    } else {
      throw new UnimplementedError('TODO(paulberry)');
    }
    return _SingleNullabilityFix._(source, kind);
  }

  _SingleNullabilityFix._(this.source, this.kind);

  /// TODO(paulberry): do something better
  Location get location => null;
}
