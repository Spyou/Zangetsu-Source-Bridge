import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

void main() {
  test('unmodified MangaDex JS source reaches manga pages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      final path = request.uri.path;
      Object response;
      if (path == '/manga') {
        response = {
          'data': [
            {
              'id': 'manga-1',
              'attributes': {
                'title': {'en': 'Fixture title'},
              },
              'relationships': [],
            },
          ],
        };
      } else if (path == '/manga/manga-1') {
        response = {
          'data': {
            'id': 'manga-1',
            'attributes': {
              'description': {'en': 'Fixture description'},
              'tags': [],
              'status': 'ongoing',
            },
            'relationships': [],
          },
        };
      } else if (path == '/manga/manga-1/feed') {
        response = {
          'limit': 500,
          'total': 1,
          'data': [
            {
              'id': 'chapter-1',
              'attributes': {
                'chapter': '1',
                'title': 'Start',
                'publishAt': '2026-01-01T00:00:00Z',
              },
              'relationships': [],
            },
          ],
        };
      } else if (path == '/at-home/server/chapter-1') {
        response = {
          'baseUrl': 'https://images.example.com',
          'chapter': {
            'hash': 'fixture-hash',
            'data': ['page-1.jpg'],
          },
        };
      } else {
        request.response.statusCode = HttpStatus.notFound;
        response = {'error': 'Unknown fixture URL'};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });

    final runtime = MangayomiRuntimeWorker(
      MSource(
        id: 810342358,
        name: 'MangaDex',
        baseUrl: 'https://mangadex.org',
        apiUrl: 'http://127.0.0.1:${server.port}',
        lang: 'en',
      ),
      File('test/fixtures/mangadex.js').readAsStringSync(),
      MangayomiCodeLanguage.javascript,
    );
    addTearDown(runtime.dispose);

    final popular = await runtime.getPopular(1);
    expect(popular.list.single.name, 'Fixture title');
    final detail = await runtime.getDetail(popular.list.single.link!);
    expect(detail.chapters?.single.url, 'chapter-1');
    final pages = await runtime.getPageList(detail.chapters!.single.url!);
    expect(
      pages.single.url,
      'https://images.example.com/data/fixture-hash/page-1.jpg',
    );
  });

  test('unmodified KissKh Dart source reaches a video link', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          request.uri.path.startsWith('/api/Sub/')
              ? <Object>[]
              : {'Video': 'https://videos.example.com/episode.m3u8'},
        ),
      );
      await request.response.close();
    });
    final runtime = MangayomiRuntimeWorker(
      MSource(
        id: 1,
        name: 'KissKh',
        baseUrl: 'http://127.0.0.1:${server.port}',
        lang: 'en',
      ),
      File('test/fixtures/kisskh.dart').readAsStringSync(),
      MangayomiCodeLanguage.dart,
    );
    addTearDown(runtime.dispose);

    final videos = await runtime.getVideoList(
      'http://127.0.0.1:${server.port}/api/DramaList/Episode/1.png?err=false',
    );
    expect(videos.single.url, 'https://videos.example.com/episode.m3u8');
  });

  test('unmodified NovelFire JS source reaches chapter text', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<html><div id="content"><p>Fixture chapter text.</p></div></html>',
      );
      await request.response.close();
    });
    final runtime = MangayomiRuntimeWorker(
      MSource(
        id: 1,
        name: 'NovelFire',
        baseUrl: 'http://127.0.0.1:${server.port}',
        lang: 'en',
      ),
      File('test/fixtures/novelfire.js').readAsStringSync(),
      MangayomiCodeLanguage.javascript,
    );
    addTearDown(runtime.dispose);

    final html = await runtime.getHtmlContent(
      '',
      'http://127.0.0.1:${server.port}/chapter/1',
    );
    expect(html, contains('Fixture chapter text.'));
  });

  test('unmodified MangaPark Dart source keeps manga page headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<div data-name="image-item"><img src="https://images.example.com/1.jpg"></div>',
      );
      await request.response.close();
    });
    final runtime = MangayomiRuntimeWorker(
      MSource(
        id: 2,
        name: 'MangaPark',
        baseUrl: 'http://127.0.0.1:${server.port}',
        lang: 'en',
      ),
      File('test/fixtures/mangapark.dart').readAsStringSync(),
      MangayomiCodeLanguage.dart,
    );
    addTearDown(runtime.dispose);
    final chapterUrl = 'http://127.0.0.1:${server.port}/chapter/1';

    final pages = await runtime.getPageList(chapterUrl);
    expect(pages.single.url, 'https://images.example.com/1.jpg');
    expect(pages.single.headers?['referer'], chapterUrl);
  });

  test('unmodified 360zy JS source returns a video link', () async {
    final runtime = MangayomiRuntimeWorker(
      MSource(id: 1, name: '360zy', baseUrl: 'https://360zy.com', lang: 'zh'),
      File('test/fixtures/360zy.js').readAsStringSync(),
      MangayomiCodeLanguage.javascript,
      preferences: {'url': 'https://360zy.com'},
    );
    addTearDown(runtime.dispose);
    const url = 'https://videos.example.com/episode.m3u8';
    final videos = await runtime.getVideoList(url);
    expect(videos.single.url, url);
    expect(videos.single.quality, 'HLS');
  });

  test('unmodified RoyalRoad Dart source reaches novel text', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<div class="chapter-inner"><p>Fixture novel dialogue.</p></div>',
      );
      await request.response.close();
    });
    final runtime = MangayomiRuntimeWorker(
      MSource(
        id: 3,
        name: 'RoyalRoad',
        baseUrl: 'https://royalroad.com',
        lang: 'en',
      ),
      File('test/fixtures/royalroad.dart').readAsStringSync(),
      MangayomiCodeLanguage.dart,
    );
    addTearDown(runtime.dispose);
    final html = await runtime.getHtmlContent(
      '',
      'http://127.0.0.1:${server.port}/chapter/1',
    );
    expect(html, contains('Fixture novel dialogue.'));
  });
}
