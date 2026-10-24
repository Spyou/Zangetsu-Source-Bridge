import 'package:flutter_test/flutter_test.dart';
import 'package:d4rt/d4rt.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

class Box {
  int add(int a, int b) => a + b;
}

void main() {
  test('d4rt instance invoke', () {
    final d = D4rt();
    d.execute(
      source: '''
      main() { return 1; }
    ''',
    );
    expect(d.invoke('x', []), isNull, skip: 'not used');
  }, skip: true);

  test('d4rt returns instance and invokes method', () {
    final d = D4rt();
    d.execute(
      source: '''
      class Calc {
        int add(int a, int b) => a + b;
      }
      main() { return Calc(); }
    ''',
    );
    expect(d.invoke('add', [2, 3]), 5);
  });

  test('javascript source rejection includes its message', () async {
    final runtime = JsSourceRuntime(
      MSource(id: 1, name: 'Broken', baseUrl: 'https://example.com'),
      '''
class DefaultExtension extends MProvider {
  async getPopular(page) { throw new Error('deliberate failure'); }
}
''',
    );
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.getPopular(1),
      throwsA(
        predicate((error) => error.toString().contains('deliberate failure')),
      ),
    );
  });

  test(
    'javascript runtime returns video, manga pages, and novel text',
    () async {
      final runtime = JsSourceRuntime(
        MSource(id: 2, name: 'Fixture', baseUrl: 'https://example.com'),
        '''
class DefaultExtension extends MProvider {
  async getVideoList(url) {
    return [{url: 'https://example.com/video.m3u8', quality: '1080p',
      originalUrl: url, headers: {Referer: 'https://example.com/'}}];
  }
  async getPageList(url) { return [{url: 'https://example.com/page.jpg',
    headers: {Referer: 'https://example.com/'}}]; }
  async getHtmlContent(name, url) { return '<p>Chapter text</p>'; }
}
''',
      );
      addTearDown(runtime.dispose);

      final videos = await runtime.getVideoList('https://example.com/episode');
      expect(videos.single.url, 'https://example.com/video.m3u8');
      expect(videos.single.headers?['Referer'], 'https://example.com/');
      final pages = await runtime.getPageList('chapter');
      expect(pages.single.url, 'https://example.com/page.jpg');
      expect(pages.single.headers?['Referer'], 'https://example.com/');
      expect(
        await runtime.getHtmlContent('Novel', 'chapter'),
        '<p>Chapter text</p>',
      );
    },
  );

  test('dart runtime returns video, manga pages, and novel text', () async {
    final runtime = DartSourceRuntime(
      MSource(id: 3, name: 'Fixture', baseUrl: 'https://example.com'),
      '''
import 'package:mangayomi/bridge_lib.dart';
class Fixture extends MProvider {
  Fixture(this.source);
  MSource source;
  Future<List<MVideo>> getVideoList(String url) async =>
      [MVideo('https://example.com/video.m3u8', '1080p', url)];
  Future<List<String>> getPageList(String url) async =>
      ['https://example.com/page.jpg'];
  Future<String> getHtmlContent(String name, String url) async =>
      '<p>Chapter text</p>';
}
Fixture main(MSource source) => Fixture(source);
''',
    );
    addTearDown(runtime.dispose);

    final videos = await runtime.getVideoList('https://example.com/episode');
    expect(videos.single.url, 'https://example.com/video.m3u8');
    expect(
      (await runtime.getPageList('chapter')).single.url,
      'https://example.com/page.jpg',
    );
    expect(
      await runtime.getHtmlContent('Novel', 'chapter'),
      '<p>Chapter text</p>',
    );
  });
}
