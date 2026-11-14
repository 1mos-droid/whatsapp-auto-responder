import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_controller/api_service.dart';

void main() {
  test(
    'status request authenticates and parses connection diagnostics',
    () async {
      final api = ApiService(
        baseUrl: 'https://example.test/',
        apiKey: 'private',
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://example.test/status');
          expect(request.headers['x-api-key'], 'private');
          return http.Response(
            jsonEncode({
              'isActive': true,
              'systemPrompt': 'Be kind.',
              'allowedChats': ['15551234567@s.whatsapp.net'],
              'runtime': {'connection': 'open', 'sent': 4},
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final status = await api.fetchStatus();
      expect(status.isActive, isTrue);
      expect(status.connection, 'open');
      expect(status.sent, 4);
    },
  );
  test(
    'active requests send an explicit state instead of blindly toggling',
    () async {
      final api = ApiService(
        apiKey: 'test',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {'isActive': false});
          return http.Response('{"isActive":false}', 200);
        }),
      );
      addTearDown(api.close);
      expect(await api.setActive(false), isFalse);
    },
  );
  test('missing key fails before any request', () async {
    final api = ApiService(
      client: MockClient(
        (_) async => fail('Must not send an unauthenticated request'),
      ),
    );
    addTearDown(api.close);
    await expectLater(api.fetchStatus(), throwsA(isA<ApiException>()));
  });
  test('unauthorized response explains the key problem', () async {
    final api = ApiService(
      apiKey: 'wrong',
      client: MockClient((_) async => http.Response('Unauthorized', 401)),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchStatus(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );
  });
  test('timeout terminates waiting and explains uncertain saves', () async {
    final api = ApiService(
      apiKey: 'test',
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(api.close);
    await expectLater(
      api.setActive(true),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('whether your change was saved'),
        ),
      ),
    );
  });
  test('server validation errors retain useful details', () async {
    final api = ApiService(
      apiKey: 'test',
      client: MockClient(
        (_) async => http.Response('{"error":"Enter a valid chat ID."}', 400),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.addChat('bad'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Enter a valid chat ID.',
        ),
      ),
    );
  });
  test(
    'invalid JSON and incompatible schemas become readable errors',
    () async {
      for (final body in ['<html>proxy error</html>', '{}']) {
        final api = ApiService(
          apiKey: 'test',
          client: MockClient((_) async => http.Response(body, 200)),
        );
        await expectLater(api.fetchStatus(), throwsA(isA<ApiException>()));
        api.close();
      }
    },
  );
  test('client network exceptions are handled', () async {
    final api = ApiService(
      apiKey: 'test',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchStatus(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Cannot reach'),
        ),
      ),
    );
  });
}
