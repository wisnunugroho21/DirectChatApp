import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tms_connect/api.dart';

void main() {
  test('API sends bearer credentials and parses JSON', () async {
    final api = Api(
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.url.path, '/api/users');
        return http.Response('[{"username":"alice"}]', 200);
      }),
    )..token = 'test-token';
    addTearDown(api.dispose);
    expect((await api.request('GET', '/api/users'))[0]['username'], 'alice');
  });
  test('401 expires the local session and preserves server message', () async {
    var expired = false;
    final api =
        Api(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({'message': 'Session expired'}),
                401,
              ),
            ),
          )
          ..token = 'expired'
          ..onUnauthorized = () => expired = true;
    addTearDown(api.dispose);
    await expectLater(
      api.request('GET', '/api/users'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Session expired',
        ),
      ),
    );
    expect(expired, isTrue);
  });
  test('attachments reject oversized uploads before network IO', () async {
    final api = Api(
      client: MockClient((_) async => throw StateError('Must not send')),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.upload(
        'id',
        http.Response('x' * (25 * 1024 * 1024 + 1), 200).bodyBytes,
        'a.txt',
        'text/plain',
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
