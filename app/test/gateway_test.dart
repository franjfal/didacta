/// Tests for the gateway, which is the seam the whole app is written against.
///
/// Two things matter here more than anything else:
///
/// * a gateway that **cannot** write must say so, because `canWrite` is what
///   every editor consults before offering a save button, and an editor that
///   offers one and then fails has already cost someone their work;
/// * a conflict must arrive as a conflict, not as a generic failure, because
///   the correct response to it is "reload" and the wrong one is "retry".
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/model/catalogue.dart';

Unit unitFor(String path) => Unit.fromJson({
  'id': path.replaceAll('/', '.'),
  'path': path,
  'area': path.split('/').first,
  'kind': 'theory',
  'category': 'a',
  'topic': 'b',
  'tags': const <String>[],
  'title': const {'es': 'Título'},
  'reference': 'es',
  'languages': const {
    'es': {'status': 'source', 'exists': true},
    'va': {'status': 'missing', 'exists': false},
  },
  'prerequisites': const <String>[],
  'objectives': const <String>[],
  'usedBy': const <Map<String, String>>[],
  'warnings': const <String>[],
});

void main() {
  group('UnitPaths', () {
    test('a language file sits inside the unit directory', () {
      // Getting this wrong means editing the wrong file, so it is pinned.
      final unit = unitFor('content/analysis/normed/definition');
      expect(unit.fileFor('es'), 'content/analysis/normed/definition/es.tex');
      expect(unit.fileFor('va'), 'content/analysis/normed/definition/va.tex');
      expect(unit.metadataPath, 'content/analysis/normed/definition/unit.yaml');
    });
  });

  group('UnconfiguredGateway', () {
    test('cannot write, and refuses reads with an explanation', () async {
      const gateway = UnconfiguredGateway();
      expect(gateway.canWrite, isFalse);
      expect(gateway.kind, GatewayKind.none);
      await expectLater(
        gateway.read('content/a/es.tex'),
        throwsA(
          isA<ContentException>().having(
            (e) => e.kind,
            'kind',
            ContentFailure.unconfigured,
          ),
        ),
      );
    });

    test('carries the reason it was given, so Ajustes can explain', () {
      const gateway = UnconfiguredGateway('Sin API ni token.');
      expect(gateway.describe(), 'Sin API ni token.');
    });
  });
}
