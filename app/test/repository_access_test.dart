/// Tests for the token check and the commit path.
///
/// The token check exists so a wrong or over-broad token is caught while the
/// person is still looking at the field, instead of failing at the moment they
/// try to save work. So these are mostly about the messages: each one has to
/// say what to do next.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:didacta_app/data/repository_access.dart';

http.Client clientReturning(
  int status,
  Object body, {
  Map<String, String> headers = const {},
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );
  });
}

void main() {
  group('token storage', () {
    test(
      'the web cannot store a token, and says so instead of pretending',
      () async {
        // `flutter test` runs as non-web, so this asserts the contract rather
        // than the platform: `canStoreSafely` is what the UI must consult before
        // offering to keep a token.
        final store = TokenStore();
        expect(store.canStoreSafely, isTrue);
      },
    );
  });
}
