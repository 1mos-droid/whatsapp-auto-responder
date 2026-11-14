import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_controller/api_service.dart';
import 'package:whatsapp_controller/main.dart';

Map<String, dynamic> status({bool active = false}) => {
  'isActive': active,
  'systemPrompt': 'Be helpful.',
  'allowedChats': <String>[],
  'runtime': {'connection': 'open', 'sent': 3, 'pending': 0, 'failed': 0},
};

void main() {
  testWidgets('dashboard reports connection and empty allowlist', (
    tester,
  ) async {
    final api = ApiService(
      apiKey: 'test',
      client: MockClient((_) async => http.Response(jsonEncode(status()), 200)),
    );
    addTearDown(api.close);
    await tester.pumpWidget(StealthApp(apiService: api));
    await tester.pumpAndSettle();
    expect(find.text('Responder Control'), findsOneWidget);
    expect(find.text('WhatsApp connected'), findsOneWidget);
    expect(find.text('No chats allowed yet.'), findsOneWidget);
    expect(find.text('3 sent'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('failed connection offers retry and settings', (tester) async {
    final api = ApiService(
      apiKey: 'test',
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    addTearDown(api.close);
    await tester.pumpWidget(StealthApp(apiService: api));
    await tester.pumpAndSettle();
    expect(
      find.text('Access denied. Check your control API key.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Connection settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('controls lock until an active-state request completes', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    bool active = false;
    final api = ApiService(
      apiKey: 'test',
      client: MockClient((request) async {
        if (request.method == 'POST') {
          expect(jsonDecode(request.body), {'isActive': true});
          active = true;
          return gate.future;
        }
        return http.Response(jsonEncode(status(active: active)), 200);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(StealthApp(apiService: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(find.text('Replies paused'), findsOneWidget);
    gate.complete(http.Response('{"isActive":true}', 200));
    await tester.pumpAndSettle();
    expect(find.text('Replies enabled'), findsWidgets);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'pending network response after leaving screen never calls setState',
    (tester) async {
      final gate = Completer<http.Response>();
      final api = ApiService(
        apiKey: 'test',
        client: MockClient((_) => gate.future),
      );
      addTearDown(api.close);
      await tester.pumpWidget(StealthApp(apiService: api));
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete(http.Response(jsonEncode(status()), 200));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('refresh preserves unsaved prompt edits', (tester) async {
    final api = ApiService(
      apiKey: 'test',
      client: MockClient((_) async => http.Response(jsonEncode(status()), 200)),
    );
    addTearDown(api.close);
    await tester.pumpWidget(StealthApp(apiService: api));
    await tester.pumpAndSettle();
    final prompt = find.byType(TextField).last;
    await tester.ensureVisible(prompt);
    await tester.enterText(prompt, 'My unsaved draft');
    await tester.tap(find.byTooltip('Refresh status'));
    await tester.pumpAndSettle();
    expect(find.text('My unsaved draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'connection dialog pauses polling and closes without lifecycle errors',
    (tester) async {
      int requests = 0;
      final api = ApiService(
        apiKey: 'test',
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(status()), 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(StealthApp(apiService: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Connection settings'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to your server'), findsOneWidget);
      await tester.pump(const Duration(seconds: 21));
      expect(requests, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('narrow screen and large text stay usable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiService(
      apiKey: 'test',
      client: MockClient((_) async => http.Response(jsonEncode(status()), 200)),
    );
    addTearDown(api.close);
    await tester.pumpWidget(StealthApp(apiService: api));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Reply instructions'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
