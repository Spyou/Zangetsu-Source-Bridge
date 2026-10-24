import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = MSource(id: 1, name: 'Proof', baseUrl: 'https://example.com');

  test('JavaScript worker returns source results', () async {
    final worker = MangayomiRuntimeWorker(source, '''
class DefaultExtension extends MProvider {
  async getPageList(url) { return [{url: url, headers: {Referer: 'https://example.com'}}]; }
  async getHtmlContent(name, url) { return '<p>ready</p>'; }
}
''', MangayomiCodeLanguage.javascript);
    addTearDown(worker.dispose);

    final pages = await worker.getPageList('https://example.com/page.jpg');
    expect(pages.single.url, 'https://example.com/page.jpg');
    expect(pages.single.headers?['Referer'], 'https://example.com');
    expect(await worker.getHtmlContent('', ''), '<p>ready</p>');
  });

  test('Dart worker returns source results', () async {
    final worker = MangayomiRuntimeWorker(source, '''
import 'package:mangayomi/bridge_lib.dart';
class Proof extends MProvider {
  Proof(this.source);
  MSource source;
  Future<List<MVideo>> getVideoList(String url) async => [MVideo(url, 'test', url)];
}
Proof main(MSource source) => Proof(source);
''', MangayomiCodeLanguage.dart);
    addTearDown(worker.dispose);

    final videos = await worker.getVideoList('https://example.com/video.m3u8');
    expect(videos.single.url, 'https://example.com/video.m3u8');
  });

  test(
    'stalled JavaScript call times out and stops its worker',
    () async {
      final worker = MangayomiRuntimeWorker(
        source,
        '''
class DefaultExtension extends MProvider {
  async getPageList(url) { return new Promise(() => {}); }
}
''',
        MangayomiCodeLanguage.javascript,
        callTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(worker.dispose);

      await expectLater(
        worker.getPageList('chapter'),
        throwsA(isA<TimeoutException>()),
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    'cancel stops a call and restarts the worker on the next call',
    () async {
      final worker = MangayomiRuntimeWorker(source, '''
class DefaultExtension extends MProvider {
  async getPageList(url) {
    if (url === 'slow') return new Promise(() => {});
    return [url];
  }
}
''', MangayomiCodeLanguage.javascript);
      addTearDown(worker.dispose);

      final pending = worker.getPageList('slow');
      final cancelled = expectLater(pending, throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      worker.cancel();
      await cancelled;
      expect(
        (await worker.getPageList('https://example.com/page')).single.url,
        'https://example.com/page',
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
