// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server/src/services/correction/fix_internal.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AddAwaitTest);
  });
}

@reflectiveTest
class AddAwaitTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.ADD_AWAIT;

  @override
  String get lintCode => LintNames.unawaited_futures;

  test_intLiteral() async {
    await resolveTestUnit('''
Future doSomething() => new Future();

void main() async {
  doSomething()/*LINT*/;
}
''');
    await assertHasFix('''
Future doSomething() => new Future();

void main() async {
  await doSomething()/*LINT*/;
}
''');
  }
}
