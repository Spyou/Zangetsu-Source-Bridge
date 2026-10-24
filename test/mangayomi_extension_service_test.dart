import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

void main() {
  test('installs JavaScript source from repository directory URL', () async {
    final directory = Directory(
      path.join(
        Directory.current.path,
        'build',
        'extension-directory-code-test',
      ),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    addTearDown(() => directory.delete(recursive: true));
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      if (request.url.path.endsWith('/javascript/')) {
        return http.Response('', 404);
      }
      if (request.url.path.endsWith('/javascript/novel/src/en/NovelFire.js')) {
        return http.Response('class DefaultExtension {}', 200);
      }
      return http.Response('', 404);
    });
    final repository = Uri.parse('https://repo.example.com/novel_index.json');
    final source = MangayomiSource.fromManifest({
      'id': 123,
      'name': 'NovelFire',
      'baseUrl': 'https://novelfire.example.com',
      'sourceCodeUrl': 'https://repo.example.com/javascript/',
      'version': '1',
      'itemType': 2,
      'sourceCodeLanguage': 1,
      'lang': 'en',
    }, repository);
    final service = MangayomiExtensionService(directory, client: client);

    final installed = await service.install(source);

    expect(
      await installed.codeFile.readAsString(),
      'class DefaultExtension {}',
    );
    expect(requested, [
      Uri.parse(
        'https://repo.example.com/javascript/novel/src/en/NovelFire.js',
      ),
    ]);
    service.dispose();
    client.close();
  });

  test(
    'install survives restart, update replaces code, uninstall removes it',
    () async {
      final directory = Directory(
        path.join(Directory.current.path, 'build', 'extension-service-test'),
      );
      if (await directory.exists()) await directory.delete(recursive: true);
      addTearDown(() => directory.delete(recursive: true));
      var code = 'class DefaultExtension {}';
      final client = MockClient((request) async {
        if (request.url.path.endsWith('.js')) return http.Response(code, 200);
        return http.Response(
          jsonEncode([
            {
              'id': 123,
              'name': 'Example',
              'baseUrl': 'https://content.example.com',
              'sourceCodeUrl': 'https://repo.example.com/source.js',
              'version': code.length.toString(),
              'itemType': 0,
              'sourceCodeLanguage': 1,
              'lang': 'en',
            },
          ]),
          200,
        );
      });
      final service = MangayomiExtensionService(directory, client: client);
      final url = Uri.parse('https://repo.example.com/index.json');
      final source = (await service.fetchIndex(url)).single;
      final first = await service.install(source);
      expect(await first.codeFile.readAsString(), code);

      final reopened = MangayomiExtensionService(directory, client: client);
      expect((await reopened.installed()).single.source.key, source.key);
      code = 'class DefaultExtension { getPopular() {} }';
      final updated = (await reopened.fetchIndex(url)).single;
      final second = await reopened.install(updated);
      expect(second.source.key, first.source.key);
      expect(await second.codeFile.readAsString(), code);
      expect(await first.codeFile.exists(), isFalse);

      await reopened.uninstall(source.key);
      expect(await reopened.installed(), isEmpty);
      expect(await second.codeFile.exists(), isFalse);
      service.dispose();
      reopened.dispose();
      client.close();
    },
  );

  test('rejected download keeps existing installation', () async {
    final directory = Directory(
      path.join(
        Directory.current.path,
        'build',
        'extension-service-error-test',
      ),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    addTearDown(() => directory.delete(recursive: true));
    var status = 200;
    final client = MockClient(
      (request) async => http.Response('working code', status),
    );
    final source = MangayomiSource.fromManifest({
      'id': 123,
      'name': 'Example',
      'baseUrl': 'https://content.example.com',
      'sourceCodeUrl': 'https://repo.example.com/source.js',
      'version': '1',
      'itemType': 1,
      'sourceCodeLanguage': 1,
      'lang': 'en',
    }, Uri.parse('https://repo.example.com/index.json'));
    final service = MangayomiExtensionService(directory, client: client);
    final installed = await service.install(source);
    status = 503;
    await expectLater(service.install(source), throwsA(isA<HttpException>()));
    expect(
      (await service.installed()).single.codeFile.path,
      installed.codeFile.path,
    );
    expect(await installed.codeFile.readAsString(), 'working code');
    service.dispose();
    client.close();
  });

  test('rejects a code download redirected to HTTP', () async {
    final directory = Directory(
      path.join(
        Directory.current.path,
        'build',
        'extension-service-redirect-test',
      ),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient(
      (request) async => http.Response(
        '',
        302,
        headers: {'location': 'http://untrusted.example.com/source.js'},
      ),
    );
    final source = MangayomiSource.fromManifest({
      'id': 123,
      'name': 'Example',
      'baseUrl': 'https://content.example.com',
      'sourceCodeUrl': 'https://repo.example.com/source.js',
      'version': '1',
      'itemType': 1,
      'sourceCodeLanguage': 1,
      'lang': 'en',
    }, Uri.parse('https://repo.example.com/index.json'));
    final service = MangayomiExtensionService(directory, client: client);
    await expectLater(service.install(source), throwsA(isA<HttpException>()));
    expect(await service.installed(), isEmpty);
    service.dispose();
    client.close();
  });

  test(
    'adds a repository with available indexes and remembers its URL',
    () async {
      final directory = Directory(
        path.join(Directory.current.path, 'build', 'extension-repository-test'),
      );
      if (await directory.exists()) await directory.delete(recursive: true);
      addTearDown(() => directory.delete(recursive: true));
      final client = MockClient((request) async {
        if (request.url.path.endsWith('anime_index.json')) {
          return http.Response('', 404);
        }
        final type = request.url.path.endsWith('novel_index.json') ? 2 : 0;
        return http.Response(
          jsonEncode([
            {
              'id': 123,
              'name': 'Example',
              'baseUrl': 'https://content.example.com',
              'sourceCodeUrl': 'https://repo.example.com/source.js',
              'version': '1',
              'itemType': type,
              'sourceCodeLanguage': 1,
              'lang': 'en',
            },
          ]),
          200,
        );
      });
      final service = MangayomiExtensionService(directory, client: client);
      final url = Uri.parse('https://repo.example.com/extensions/');

      final sources = await service.addRepository(url);
      expect(sources.map((source) => source.contentType), [
        MangayomiContentType.manga,
        MangayomiContentType.novel,
      ]);
      final reopened = MangayomiExtensionService(directory, client: client);
      expect(await reopened.repositories(), [url]);
      expect((await reopened.refreshRepository(url)).length, 2);
      await reopened.removeRepository(url);
      expect(await reopened.repositories(), isEmpty);
      service.dispose();
      reopened.dispose();
      client.close();
    },
  );

  test('repository root finds manga held only in manga_index.json', () async {
    final directory = Directory(
      path.join(Directory.current.path, 'build', 'extension-manga-index-test'),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient((request) async {
      if (request.url.path.endsWith('manga_index.json')) {
        return http.Response(
          jsonEncode([
            {
              'id': 123,
              'name': 'MangaOnly',
              'baseUrl': 'https://manga.example.com',
              'sourceCodeUrl': 'https://repo.example.com/source.js',
              'version': '1',
              'itemType': 0,
              'sourceCodeLanguage': 1,
              'lang': 'en',
            },
          ]),
          200,
        );
      }
      return http.Response('', 404);
    });
    final service = MangayomiExtensionService(directory, client: client);
    final url = Uri.parse('https://repo.example.com/extensions/');
    final sources = await service.addRepository(url);
    expect(sources.single.contentType, MangayomiContentType.manga);
    service.dispose();
    client.close();
  });

  test(
    'novel repository add tolerates multilingual anime duplicates',
    () async {
      final directory = Directory(
        path.join(
          Directory.current.path,
          'build',
          'extension-multilingual-index-test',
        ),
      );
      if (await directory.exists()) await directory.delete(recursive: true);
      addTearDown(() => directory.delete(recursive: true));
      Map<String, Object> source(int type, String language, int id) => {
        'id': id,
        'name': 'Example$id',
        'baseUrl': 'https://content.example.com',
        'sourceCodeUrl': 'https://repo.example.com/source$id.js',
        'version': '1',
        'itemType': type,
        'sourceCodeLanguage': 1,
        'lang': language,
      };
      final client = MockClient((request) async {
        if (request.url.path.endsWith('anime_index.json')) {
          return http.Response(
            jsonEncode([source(1, 'en', 100), source(1, 'ja', 100)]),
            200,
          );
        }
        if (request.url.path.endsWith('novel_index.json')) {
          return http.Response(jsonEncode([source(2, 'en', 200)]), 200);
        }
        return http.Response('', 404);
      });
      final service = MangayomiExtensionService(directory, client: client);

      final sources = await service.addRepository(
        Uri.parse('https://repo.example.com/extensions/novel_index.json'),
      );

      expect(sources, hasLength(2));
      expect(
        sources
            .singleWhere(
              (source) => source.contentType == MangayomiContentType.video,
            )
            .language,
        'all',
      );
      expect(
        sources
            .singleWhere(
              (source) => source.contentType == MangayomiContentType.novel,
            )
            .name,
        'Example200',
      );
      expect(await service.repositories(), [
        Uri.parse('https://repo.example.com/extensions/'),
      ]);
      service.dispose();
      client.close();
    },
  );

  test('conflicting entries across repository indexes are rejected', () async {
    final directory = Directory(
      path.join(Directory.current.path, 'build', 'extension-conflict-test'),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final client = MockClient((request) async {
      final version = request.url.pathSegments.last == 'index.json' ? '1' : '2';
      return http.Response(
        jsonEncode([
          {
            'id': 123,
            'name': 'Example',
            'baseUrl': 'https://content.example.com',
            'sourceCodeUrl': 'https://repo.example.com/source.js',
            'version': version,
            'itemType': 0,
            'sourceCodeLanguage': 1,
            'lang': 'en',
          },
        ]),
        200,
      );
    });
    final service = MangayomiExtensionService(directory, client: client);
    await expectLater(
      service.refreshRepository(Uri.parse('https://repo.example.com/ext/')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Conflicting source'),
        ),
      ),
    );
    service.dispose();
    client.close();
  });

  test('index file URLs of one repository collapse to a single root', () async {
    final directory = Directory(
      path.join(Directory.current.path, 'build', 'extension-root-add-test'),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final client = MockClient((request) async {
      final type = request.url.path.endsWith('anime_index.json') ? 1 : 0;
      return http.Response(
        jsonEncode([
          {
            'id': type + 1,
            'name': 'Source$type',
            'baseUrl': 'https://s$type.example.com',
            'sourceCodeUrl': 'https://repo.example.com/$type.js',
            'version': '1',
            'itemType': type,
            'sourceCodeLanguage': 1,
            'lang': 'en',
          },
        ]),
        200,
      );
    });
    final service = MangayomiExtensionService(directory, client: client);
    final root = Uri.parse('https://repo.example.com/ext/');
    final sources = await service.addRepository(
      Uri.parse('https://repo.example.com/ext/anime_index.json'),
    );
    expect(sources.map((s) => s.contentType).toSet(), {
      MangayomiContentType.manga,
      MangayomiContentType.video,
    });
    await service.addRepository(
      Uri.parse('https://repo.example.com/ext/index.json'),
    );
    expect(await service.repositories(), [root]);
    service.dispose();
    client.close();
  });

  test('stored index and directory variants load as one repository', () async {
    final directory = Directory(
      path.join(Directory.current.path, 'build', 'extension-root-load-test'),
    );
    await directory.create(recursive: true);
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    await File(path.join(directory.path, 'repositories.json')).writeAsString(
      jsonEncode([
        'https://repo.example.com/ext/anime_index.json',
        'https://repo.example.com/ext/',
        'https://repo.example.com/ext/index.json',
        'https://repo.example.com/other/custom.json',
      ]),
    );
    final client = MockClient((request) async => http.Response('', 404));
    final service = MangayomiExtensionService(directory, client: client);
    expect(await service.repositories(), [
      Uri.parse('https://repo.example.com/ext/'),
      Uri.parse('https://repo.example.com/other/custom.json'),
    ]);
    service.dispose();
    client.close();
  });

  test('direct index failure does not save a repository', () async {
    final directory = Directory(
      path.join(Directory.current.path, 'build', 'extension-direct-index-test'),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    addTearDown(() => directory.delete(recursive: true));
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      return http.Response('', 404);
    });
    final service = MangayomiExtensionService(directory, client: client);
    final direct = Uri.parse('https://repo.example.com/custom.json');
    await expectLater(
      service.addRepository(direct),
      throwsA(isA<HttpException>()),
    );
    expect(requested, [direct]);
    expect(await service.repositories(), isEmpty);
    await expectLater(
      service.addRepository(Uri.parse('http://repo.example.com/')),
      throwsFormatException,
    );
    service.dispose();
    client.close();
  });

  test('installed source runs from its saved code after restart', () async {
    final directory = Directory(
      path.join(Directory.current.path, 'build', 'extension-offline-test'),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient(
      (request) async => http.Response('''
class DefaultExtension extends MProvider {
  async getPageList(url) { return [url]; }
}
''', 200),
    );
    final source = MangayomiSource.fromManifest({
      'id': 123,
      'name': 'Offline example',
      'baseUrl': 'https://content.example.com',
      'sourceCodeUrl': 'https://repo.example.com/source.js',
      'version': '1',
      'itemType': 0,
      'sourceCodeLanguage': 1,
      'lang': 'en',
    }, Uri.parse('https://repo.example.com/index.json'));
    final service = MangayomiExtensionService(directory, client: client);
    await service.install(source);
    service.dispose();
    client.close();

    final reopened = MangayomiExtensionService(directory);
    final saved = (await reopened.installed()).single;
    final worker = MangayomiRuntimeWorker(
      saved.source.toRuntimeSource(),
      await saved.codeFile.readAsString(),
      saved.source.codeLanguage,
    );
    addTearDown(worker.dispose);
    expect(
      (await worker.getPageList(
        'https://content.example.com/page.jpg',
      )).single.url,
      'https://content.example.com/page.jpg',
    );
    reopened.dispose();
  });
}
