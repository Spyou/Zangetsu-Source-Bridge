import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

void main() {
  final repo = MangayomiRepository(Uri.parse('https://example.com/index.json'));

  Map<String, Object> entry(int type, int language) => {
    'id': 123,
    'name': 'Example',
    'baseUrl': 'http://content.example.com',
    'sourceCodeUrl': 'https://example.com/example.js',
    'version': '1.0.0',
    'itemType': type,
    'sourceCodeLanguage': language,
    'lang': 'en',
  };

  test('parses all three content types and both code languages', () {
    final sources = repo.parseIndex(
      jsonEncode([entry(0, 0), entry(1, 1), entry(2, 0)]),
    );
    expect(sources.map((e) => e.contentType), MangayomiContentType.values);
    expect(sources[1].codeLanguage, MangayomiCodeLanguage.javascript);
    expect(sources[0].key, startsWith('mg:'));
    expect(sources[0].key, isNot(sources[1].key));
    expect(
      sources[0].key,
      repo.parseIndex(jsonEncode([entry(0, 0)])).single.key,
    );
  });

  test('rejects unsafe code URLs and unknown source types', () {
    expect(
      () => repo.parseIndex(
        jsonEncode([
          entry(0, 0)..['sourceCodeUrl'] = 'http://example.com/a.js',
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => repo.parseIndex(jsonEncode([entry(3, 0)])),
      throwsFormatException,
    );
  });

  test('keeps the runtime fields across a stored manifest', () {
    final manifest = entry(1, 1)
      ..['apiUrl'] = 'https://api.example.com'
      ..['hasCloudflare'] = true
      ..['isFullData'] = true
      ..['additionalParams'] = 'fixture'
      ..['appMinVerReq'] = '0.5.0';
    final source = MangayomiSource.fromManifest(manifest, repo.url);
    final restored = MangayomiSource.fromManifest(
      source.toManifest(),
      repo.url,
    );
    expect(restored.toRuntimeSource().apiUrl, 'https://api.example.com');
    expect(restored.toRuntimeSource().hasCloudflare, isTrue);
    expect(restored.toRuntimeSource().isFullData, isTrue);
    expect(restored.toRuntimeSource().additionalParams, 'fixture');
    expect(restored.minimumAppVersion, '0.5.0');
  });

  test('rejects malformed or oversized indexes', () {
    expect(() => repo.parseIndex('{}'), throwsFormatException);
    expect(
      () => repo.parseIndex(' ' * (5 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });

  test('identity includes code language and duplicate entries fail', () {
    final dart = repo.parseIndex(jsonEncode([entry(0, 0)])).single;
    final javascript = repo.parseIndex(jsonEncode([entry(0, 1)])).single;
    expect(dart.key, isNot(javascript.key));
    expect(
      () => repo.parseIndex(jsonEncode([entry(0, 0), entry(0, 0)])),
      throwsFormatException,
    );
  });

  test('same source in sibling indexes keeps one identity', () {
    final manga = repo.parseIndex(jsonEncode([entry(0, 0)])).single;
    final sibling = MangayomiRepository(
      Uri.parse('https://example.com/novel_index.json'),
    ).parseIndex(jsonEncode([entry(0, 0)])).single;
    expect(manga.key, sibling.key);
    final otherRepo = MangayomiRepository(
      Uri.parse('https://elsewhere.example.com/index.json'),
    ).parseIndex(jsonEncode([entry(0, 0)])).single;
    expect(manga.key, isNot(otherRepo.key));
  });
}
