import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zangetsu_source_bridge/src/cloudflare_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zangetsu/mihon');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'protected requests carry the solved cookie and matching user agent',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'Cookie': 'cf_clearance=ready',
          'User-Agent': 'SolvedBrowser/1',
        },
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final client = MangayomiHttpClient(
        protected: true,
        inner: MockClient((request) async {
          expect(request.headers['Cookie'], 'cf_clearance=ready');
          expect(request.headers['User-Agent'], 'SolvedBrowser/1');
          return http.Response('ready', 200);
        }),
      );
      addTearDown(client.close);
      expect(await client.read(Uri.parse('https://example.com')), 'ready');
    },
  );

  test('unprotected sources do not query the cookie channel', () async {
    var channelCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      channelCalls++;
      return <String, String>{};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final client = MangayomiHttpClient(
      protected: false,
      inner: MockClient((request) async => http.Response('ready', 200)),
    );
    addTearDown(client.close);
    await client.read(Uri.parse('https://example.com'));
    expect(channelCalls, 0);
  });

  test(
    'a protected challenge is reported instead of parsed as content',
    () async {
      final client = MangayomiHttpClient(
        protected: true,
        inner: MockClient(
          (request) async => http.Response(
            '<html>challenge</html>',
            403,
            headers: {'server': 'cloudflare'},
          ),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.read(Uri.parse('https://example.com')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Cloudflare challenge'),
          ),
        ),
      );
    },
  );
}
