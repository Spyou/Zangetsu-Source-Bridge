import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zangetsu_source_bridge/stremio.dart';

String fixture(String name) =>
    File('test/stremio/fixtures/$name').readAsStringSync();

StremioClient clientFor(
  List<http.Request> captured,
  String body, {
  int status = 200,
  Duration timeout = const Duration(seconds: 12),
  int maxJsonBytes = 5 * 1024 * 1024,
  bool allowHttp = false,
}) {
  return StremioClient(
    httpClient: MockClient((request) async {
      captured.add(request);
      return http.Response.bytes(utf8.encode(body), status);
    }),
    timeout: timeout,
    maxJsonBytes: maxJsonBytes,
    allowHttp: allowHttp,
  );
}

void main() {
  test('catalogue keeps poster shape supplied by the addon', () async {
    final client = clientFor(
      [],
      jsonEncode({
        'metas': [
          {
            'id': 'a',
            'name': 'A',
            'posterShape': 'landscape',
            'landscapePoster': 'https://img.example/wide.jpg',
          },
          {'id': 'b', 'name': 'B', 'posterShape': 'square'},
          {'id': 'c', 'name': 'C'},
        ],
      }),
    );
    final page = await client.catalog(
      Uri.parse('https://addon.example'),
      type: 'movie',
      catalogId: 'top',
    );
    expect(page.metas.first.landscapePoster, 'https://img.example/wide.jpg');
    expect(page.metas.map((m) => m.posterShape), ['landscape', 'square', null]);
  });
  group('manifest', () {
    test('resolves an optional addon logo against its transport', () async {
      final body =
          jsonDecode(fixture('manifest_full.json')) as Map<String, dynamic>;
      body['logo'] = '/images/addon.png';
      final manifest = await clientFor(
        [],
        jsonEncode(body),
      ).manifest(Uri.parse('https://addon.example/base'));
      expect(manifest.logo, 'https://addon.example/images/addon.png');
    });

    test('keeps both catalogues and string/object resources', () async {
      final requests = <http.Request>[];
      final client = clientFor(requests, fixture('manifest_full.json'));
      final manifest = await client.manifest(
        Uri.parse('https://addon.example/configured/path?token=abc'),
      );

      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/configured/path/manifest.json');
      expect(requests.single.url.query, 'token=abc');

      expect(manifest.id, 'org.example.addon');
      expect(manifest.name, 'Example Addon');
      expect(manifest.version, '1.2.3');
      expect(manifest.catalogs, hasLength(2));
      expect(manifest.supports('catalog'), isTrue);
      expect(manifest.supports('meta'), isTrue);
      expect(manifest.supports('stream'), isTrue);
      expect(manifest.supports('subtitles'), isTrue);

      final meta = manifest.resource('meta')!;
      expect(meta.types, ['movie']);
      expect(meta.idPrefixes, ['tt']);

      final top = manifest.catalogsFor('movie').single;
      expect(
        top.extras.map((e) => e.name),
        containsAll(['search', 'skip', 'genre']),
      );
      expect(
        top.extras.firstWhere((e) => e.name == 'search').isRequired,
        isTrue,
      );
      expect(top.isSearchable, isTrue);
      expect(top.isPaged, isTrue);
      expect(top.extras.firstWhere((e) => e.name == 'genre').options, [
        'Action',
        'Drama',
      ]);

      final airing = manifest.catalogsFor('series').single;
      expect(airing.isSearchable, isTrue);

      expect(manifest.configurable, isTrue);
      expect(
        manifest.configurationUrl,
        Uri.parse('https://addon.example/setup'),
      );
    });

    test('rejects a manifest without an id', () async {
      final client = clientFor([], jsonEncode({'name': 'No id'}));
      await expectLater(
        client.manifest(Uri.parse('https://addon.example')),
        throwsA(
          isA<StremioFailure>().having(
            (e) => e.category,
            'category',
            StremioFailureCategory.invalidManifest,
          ),
        ),
      );
    });
  });

  group('requests', () {
    test('catalogues preserve optional title logos', () async {
      final body = jsonDecode(fixture('catalog_page.json')) as Map;
      (body['metas'] as List).first['logo'] = 'https://img.example/title.png';
      final page = await clientFor([], jsonEncode(body)).catalog(
        Uri.parse('https://addon.example'),
        type: 'movie',
        catalogId: 'top',
      );
      expect(page.metas.first.logo, 'https://img.example/title.png');
      expect(page.metas.last.logo, isNull);
    });

    test('catalogue extras keep their encoding and base query', () async {
      final requests = <http.Request>[];
      final client = clientFor(requests, fixture('catalog_page.json'));
      final page = await client.catalog(
        Uri.parse('https://addon.example/configured/path?token=abc'),
        type: 'movie',
        catalogId: 'top',
        search: 'batman begins',
        skip: 100,
        genre: 'Sci-Fi',
      );

      final uri = requests.single.url;
      expect(uri.query, 'token=abc');
      expect(
        uri.path,
        contains(
          '/configured/path/catalog/movie/top/'
          'search=batman%20begins&skip=100&genre=Sci-Fi.json',
        ),
      );
      expect(
        uri.pathSegments.last,
        'search=batman begins&skip=100&genre=Sci-Fi.json',
      );
      expect(page.metas, hasLength(2));
      expect(page.metas.first.id, 'tt0372784');
      expect(page.metas.last.id, 'tmdb:12345');
    });

    test('custom video ID survives stream request encoding', () async {
      final requests = <http.Request>[];
      final client = clientFor(requests, '{"streams":[]}');
      await client.streams(
        Uri.parse('https://addon.example'),
        type: 'series',
        id: 'custom:season/one?part=2',
      );
      final uri = requests.single.url;
      expect(uri.pathSegments.last, 'custom:season/one?part=2.json');
      expect(uri.path, contains('%3Fpart%3D2.json'));
    });
  });

  group('meta', () {
    test(
      'detail background prefers background then landscape poster',
      () async {
        for (final background in ['https://img.example/backdrop', null, '  ']) {
          final client = clientFor(
            [],
            jsonEncode({
              'meta': {
                'id': 'tt123',
                'type': 'movie',
                'name': 'Title',
                'background': background,
                'landscapePoster': 'https://img.example/landscape',
              },
            }),
          );
          final meta = await client.meta(
            Uri.parse('https://addon.example'),
            type: 'movie',
            id: 'tt123',
          );
          expect(
            meta!.background,
            background?.trim().isNotEmpty == true
                ? background
                : 'https://img.example/landscape',
          );
        }
      },
    );

    test('keeps videos, season zero and verified external ids', () async {
      final client = clientFor([], fixture('meta_series.json'));
      final meta = await client.meta(
        Uri.parse('https://addon.example'),
        type: 'series',
        id: 'tt0944947',
      );

      expect(meta, isNotNull);
      expect(meta!.name, 'Game of Thrones');
      expect(meta.videos, hasLength(3));
      expect(meta.videos.first.season, 0);
      expect(meta.videos.first.episode, 1);
      expect(meta.videos[1].season, 1);
      expect(meta.videos[1].episode, 1);
      expect(meta.videos[1].thumbnail, 'https://img.example/1.jpg');
      expect(meta.defaultVideoId, 'tt0944947:1:1');
      expect(meta.externalIds, {'imdb': 'tt0944947'});
      expect(meta.videos[1].streams.single.kind, StremioStreamKind.direct);
      expect(meta.videos[1].streams.single.headers, {
        'Referer': 'https://inline/',
      });
    });

    test('movie meta without videos stays valid', () async {
      final client = clientFor(
        [],
        '{"meta":{"id":"tt0372784","type":"movie","name":"Batman Begins"}}',
      );
      final meta = await client.meta(
        Uri.parse('https://addon.example'),
        type: 'movie',
        id: 'tt0372784',
      );
      expect(meta!.videos, isEmpty);
      expect(meta.externalIds, {'imdb': 'tt0372784'});
    });

    test('missing meta returns null', () async {
      final client = clientFor([], '{"meta":null}');
      expect(
        await client.meta(
          Uri.parse('https://addon.example'),
          type: 'movie',
          id: 'tt1',
        ),
        isNull,
      );
    });
  });

  group('streams', () {
    test('preserves formatted description with title fallback', () async {
      final client = clientFor(
        [],
        jsonEncode({
          'streams': [
            {
              'name': 'Addon',
              'description': 'Release\n1080p\nEnglish',
              'title': 'Fallback',
              'url': 'https://example.com/one',
            },
            {'title': 'Legacy\n720p', 'url': 'https://example.com/two'},
          ],
        }),
      );
      final streams = await client.streams(
        Uri.parse('https://addon.example'),
        type: 'movie',
        id: 'tt1',
      );
      expect(streams[0].description, 'Release\n1080p\nEnglish');
      expect(streams[1].description, 'Legacy\n720p');
    });

    test('maps every link kind and preserves fileIdx zero', () async {
      final client = clientFor([], fixture('streams_all.json'));
      final streams = await client.streams(
        Uri.parse('https://addon.example'),
        type: 'movie',
        id: 'tt0372784',
      );

      final direct = streams[0];
      expect(direct.kind, StremioStreamKind.direct);
      expect(direct.url, 'https://cdn.example/movie.m3u8');
      expect(direct.headers, {
        'Referer': 'https://site/',
        'User-Agent': 'TestUA',
      });
      expect(direct.fileName, 'movie.1080p.mkv');
      expect(direct.videoHash, 'abc');
      expect(direct.videoSize, 1234);
      expect(direct.subtitles.single.format, 'srt');

      final indexed = streams[1];
      expect(indexed.kind, StremioStreamKind.torrent);
      expect(indexed.fileIndex, 0);
      expect(indexed.infoHash, '0123456789abcdef0123456789abcdef01234567');
      expect(indexed.trackers, ['udp://tracker.example:1337/announce']);

      expect(streams[2].fileIndex, 3);
      expect(streams[2].infoHash, '0123456789abcdef0123456789abcdef01234567');

      final magnet = streams[3];
      expect(magnet.kind, StremioStreamKind.torrent);
      expect(magnet.fileIndex, 2);
      expect(magnet.infoHash, '89abcdef0123456789abcdef0123456789abcdef');
      expect(magnet.trackers, ['udp://tracker.example:1337/announce']);

      expect(streams[4].kind, StremioStreamKind.youtube);
      expect(streams[5].kind, StremioStreamKind.external);
      expect(streams[6].kind, StremioStreamKind.unsupported);
      expect(streams[7].kind, StremioStreamKind.unsupported);
      expect(streams[8].kind, StremioStreamKind.unsupported);
    });

    test('empty streams response is a valid empty list', () async {
      final client = clientFor([], '{"streams":[]}');
      expect(
        await client.streams(
          Uri.parse('https://addon.example'),
          type: 'movie',
          id: 'tt1',
        ),
        isEmpty,
      );
    });
  });

  group('subtitles', () {
    test('maps language and format and drops unsafe URLs', () async {
      final client = clientFor([], fixture('subtitles.json'));
      final subs = await client.subtitles(
        Uri.parse('https://addon.example'),
        type: 'movie',
        id: 'tt0372784',
      );
      expect(subs, hasLength(2));
      expect(subs.first.lang, 'English');
      expect(subs.first.format, 'srt');
      expect(subs.last.format, 'vtt');
    });
  });

  group('subtitles extras', () {
    test('filename, video hash and size travel in the path', () async {
      final requests = <http.Request>[];
      final client = clientFor(requests, '{"subtitles":[]}');
      await client.subtitles(
        Uri.parse('https://addon.example'),
        type: 'movie',
        id: 'tt1',
        filename: 'movie.1080p.mkv',
        videoHash: 'abc',
        videoSize: 1234,
      );
      final uri = requests.single.url;
      expect(
        uri.pathSegments.last,
        'filename=movie.1080p.mkv&videoHash=abc&videoSize=1234.json',
      );
    });
  });

  test('torrent indexes outside the native range are rejected', () async {
    final client = clientFor(
      [],
      jsonEncode({
        'streams': [
          {
            'infoHash': '0123456789abcdef0123456789abcdef01234567',
            'fileIdx': 4294967296,
          },
          {
            'url':
                'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=4294967296',
          },
        ],
      }),
    );
    final streams = await client.streams(
      Uri.parse('https://addon.example'),
      type: 'movie',
      id: 'tt1',
    );
    expect(
      streams.every((s) => s.kind == StremioStreamKind.unsupported),
      isTrue,
    );
  });

  test('magnet file selection preserves index zero', () async {
    final client = clientFor(
      [],
      jsonEncode({
        'streams': [
          {
            'url':
                'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=0',
          },
        ],
      }),
    );
    final streams = await client.streams(
      Uri.parse('https://addon.example'),
      type: 'series',
      id: 'tt1:1:1',
    );
    expect(streams.single.fileIndex, 0);
  });

  test('a slow response body times out and cancels its subscription', () async {
    var cancelled = false;
    Timer? drip;
    late StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () => drip = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => body.add([32]),
      ),
      onCancel: () {
        cancelled = true;
        drip?.cancel();
      },
    );
    final client = StremioClient(
      httpClient: MockClient.streaming(
        (request, _) async => http.StreamedResponse(body.stream, 200),
      ),
      timeout: const Duration(milliseconds: 70),
    );
    try {
      await expectLater(
        client
            .manifest(Uri.parse('https://addon.example'))
            .timeout(const Duration(milliseconds: 400)),
        throwsA(
          isA<StremioFailure>().having(
            (e) => e.category,
            'category',
            StremioFailureCategory.timeout,
          ),
        ),
      );
      expect(cancelled, isTrue);
    } finally {
      drip?.cancel();
      await body.close();
    }
  });

  test('an error response cannot hang while draining its body', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final client = StremioClient(
      httpClient: MockClient.streaming(
        (request, _) async => http.StreamedResponse(body.stream, 500),
      ),
      timeout: const Duration(milliseconds: 50),
    );
    try {
      await expectLater(
        client
            .manifest(Uri.parse('https://addon.example'))
            .timeout(const Duration(milliseconds: 300)),
        throwsA(isA<StremioFailure>()),
      );
      expect(cancelled, isTrue);
    } finally {
      await body.close();
    }
  });

  group('failures', () {
    test('malformed JSON is typed', () async {
      final client = clientFor([], 'not json');
      await expectLater(
        client.manifest(Uri.parse('https://addon.example')),
        throwsA(
          isA<StremioFailure>().having(
            (e) => e.category,
            'category',
            StremioFailureCategory.invalidJson,
          ),
        ),
      );
    });

    test('unexpected top-level type is typed', () async {
      final client = clientFor([], '[]');
      await expectLater(
        client.manifest(Uri.parse('https://addon.example')),
        throwsA(
          isA<StremioFailure>().having(
            (e) => e.category,
            'category',
            StremioFailureCategory.invalidResponse,
          ),
        ),
      );
    });

    test('HTTP errors are checked before parsing', () async {
      final client = clientFor([], '{"streams":[]}', status: 500);
      await expectLater(
        client.streams(
          Uri.parse('https://addon.example'),
          type: 'movie',
          id: 'tt1',
        ),
        throwsA(
          isA<StremioFailure>()
              .having(
                (e) => e.category,
                'category',
                StremioFailureCategory.httpStatus,
              )
              .having((e) => e.statusCode, 'status', 500),
        ),
      );
    });

    test('timeout is typed', () async {
      final client = StremioClient(
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return http.Response.bytes(utf8.encode('{}'), 200);
        }),
        timeout: const Duration(milliseconds: 30),
      );
      await expectLater(
        client.manifest(Uri.parse('https://addon.example')),
        throwsA(
          isA<StremioFailure>().having(
            (e) => e.category,
            'category',
            StremioFailureCategory.timeout,
          ),
        ),
      );
    });

    test('response size is bounded while reading', () async {
      final client = clientFor(
        [],
        fixture('manifest_full.json'),
        maxJsonBytes: 32,
      );
      await expectLater(
        client.manifest(Uri.parse('https://addon.example')),
        throwsA(
          isA<StremioFailure>().having(
            (e) => e.category,
            'category',
            StremioFailureCategory.tooLarge,
          ),
        ),
      );
    });

    test('plain http is rejected unless explicitly allowed', () async {
      final client = clientFor([], '{}');
      expect(
        () => client.manifest(Uri.parse('http://addon.example')),
        throwsA(isA<StremioFailure>()),
      );

      final allowed = clientFor(
        [],
        fixture('manifest_full.json'),
        allowHttp: true,
      );
      expect(
        await allowed.manifest(Uri.parse('http://addon.example')),
        isA<StremioManifest>(),
      );
    });

    test('https to http redirect is rejected', () async {
      final client = StremioClient(
        httpClient: MockClient((request) async {
          return http.Response.bytes(
            const [],
            302,
            headers: {'location': 'http://evil.example/x'},
          );
        }),
      );
      await expectLater(
        client.manifest(Uri.parse('https://addon.example')),
        throwsA(
          isA<StremioFailure>().having(
            (e) => e.category,
            'category',
            StremioFailureCategory.unsupportedScheme,
          ),
        ),
      );
    });

    test('follows up to five https redirects and then stops', () async {
      var hits = 0;
      final client = StremioClient(
        httpClient: MockClient((request) async {
          hits++;
          return http.Response.bytes(
            const [],
            302,
            headers: {'location': '/manifest.json'},
          );
        }),
      );
      await expectLater(
        client.manifest(Uri.parse('https://addon.example')),
        throwsA(
          isA<StremioFailure>().having(
            (e) => e.category,
            'category',
            StremioFailureCategory.tooManyRedirects,
          ),
        ),
      );
      expect(hits, 6);
    });
  });
}
