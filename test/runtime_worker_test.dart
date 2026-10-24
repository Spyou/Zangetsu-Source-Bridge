import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = MSource(id: 1, name: 'Proof', baseUrl: 'https://example.com');

  test(
    'JavaScript worker exposes settings and passes selected filters',
    () async {
      final worker = MangayomiRuntimeWorker(
        source,
        '''
class DefaultExtension extends MProvider {
  getSourcePreferences() { return [{key: 'server', listPreference: {title: 'Server', entries: ['A', 'B'], entryValues: ['a', 'b'], valueIndex: 0}}]; }
  getFilterList() { return [{type_name: 'SelectFilter', type: 'genre', name: 'Genre', state: 0, values: [{name: 'All', value: ''}, {name: 'Action', value: 'action'}]}]; }
  async search(query, page, filters) { return {list: [{name: filters[0].values[filters[0].state].name, link: '/item'}], hasNextPage: false}; }
}
''',
        MangayomiCodeLanguage.javascript,
        preferences: {'server': 'b'},
      );
      addTearDown(worker.dispose);
      expect((await worker.getSourcePreferences()).single['key'], 'server');
      final filters = await worker.getFilterList();
      filters.single['state'] = 1;
      expect((await worker.search('', 1, filters)).list.single.name, 'Action');
    },
  );

  test('Dart worker exposes source settings and filters', () async {
    final worker = MangayomiRuntimeWorker(source, '''
import 'package:mangayomi/bridge_lib.dart';
class Proof extends MProvider {
  Proof(this.source);
  MSource source;
  List<dynamic> getSourcePreferences() => [ListPreference(key: 'quality', title: 'Quality', valueIndex: 0, entries: ['High'], entryValues: ['high'])];
  List<dynamic> getFilterList() => [SelectFilter('genre', 'Genre', 0, [SelectFilterOption('All', ''), SelectFilterOption('Action', 'action')])];
  Future<MPages> search(String query, int page, FilterList filters) async => MPages([], false);
}
Proof main(MSource source) => Proof(source);
''', MangayomiCodeLanguage.dart);
    addTearDown(worker.dispose);
    expect((await worker.getSourcePreferences()).single['key'], 'quality');
    final filters = await worker.getFilterList();
    filters.single['state'] = 1;
    expect((await worker.search('', 1, filters)).list, isEmpty);
  });

  test('Dart source uses its default setting and saved override', () async {
    const code = '''
import 'package:mangayomi/bridge_lib.dart';
class Proof extends MProvider {
  Proof(this.source);
  MSource source;
  List<dynamic> getSourcePreferences() => [ListPreference(key: 'server', title: 'Server', valueIndex: 0, entries: ['A', 'B'], entryValues: ['a', 'b'])];
  Future<String> getHtmlContent(String name, String url) async => getPreferenceValue(source.id, 'server');
}
Proof main(MSource source) => Proof(source);
''';
    final initial = MangayomiRuntimeWorker(
      source,
      code,
      MangayomiCodeLanguage.dart,
    );
    addTearDown(initial.dispose);
    expect((await initial.getSourcePreferences()).single['value'], 'a');
    expect(await initial.getHtmlContent('', ''), 'a');
    final saved = MangayomiRuntimeWorker(
      source,
      code,
      MangayomiCodeLanguage.dart,
      preferences: {'server': 'b'},
    );
    addTearDown(saved.dispose);
    expect(await saved.getHtmlContent('', ''), 'b');
  });

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
