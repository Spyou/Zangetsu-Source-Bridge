import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  // Live sites change or rate-limit independently of the bridge.
  const runLive = bool.fromEnvironment('RUN_LIVE_EXTENSION_TESTS');
  group('javascript sources', () {
    test('360zy video link', () async {
      final runtime = JsSourceRuntime(
        MSource(id: 1, name: '360zy', baseUrl: 'https://360zy.com', lang: 'zh'),
        fixture('360zy.js'),
        preferences: {'url': 'https://360zy.com'},
      );
      final pages = await runtime.getPopular(1);
      expect(pages.list, isNotEmpty);
      final detail = await runtime.getDetail(pages.list.first.link!);
      expect(detail.chapters, isNotEmpty);
      final videos = await runtime.getVideoList(detail.chapters!.first.url!);
      expect(videos, isNotEmpty);
      expect(videos.first.url, contains('.m3u8'));
      runtime.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('MangaDex manga pages', () async {
      final runtime = JsSourceRuntime(
        MSource(
          id: 810342358,
          name: 'MangaDex',
          baseUrl: 'https://mangadex.org',
          apiUrl: 'https://api.mangadex.org',
          lang: 'en',
        ),
        fixture('mangadex.js'),
      );
      final pages = await runtime.getPopular(1);
      expect(pages.list, isNotEmpty);
      final detail = await runtime.getDetail(
        '/manga/a1c7c817-4e59-43b7-9365-09675a149a6f',
      );
      expect(detail.chapters, isNotEmpty);
      final pageList = await runtime.getPageList(detail.chapters!.first.url!);
      expect(pageList, isNotEmpty);
      expect(pageList.first.url, startsWith('http'));
      runtime.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('NovelFire novel text', () async {
      final runtime = JsSourceRuntime(
        MSource(
          id: 1,
          name: 'NovelFire',
          baseUrl: 'https://novelfire.net',
          lang: 'en',
        ),
        fixture('novelfire.js'),
      );
      final pages = await runtime.getPopular(1);
      expect(pages.list, isNotEmpty);
      final detail = await runtime.getDetail(pages.list.first.link!);
      expect(detail.chapters, isNotEmpty);
      final html = await runtime.getHtmlContent(
        '',
        detail.chapters!.first.url!,
      );
      expect(html, contains('<p'));
      runtime.dispose();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'NetMirror popular (blocked upstream)',
      () async {
        final runtime = JsSourceRuntime(
          MSource(
            id: 446414301,
            name: 'NetMirror',
            baseUrl: 'https://net2025.cc',
            apiUrl: 'https://net2025.cc',
            lang: 'all',
          ),
          fixture('netmirror.js'),
        );
        final prefs = await runtime.call<List>('getSourcePreferences()');
        expect(prefs, isNotEmpty);
        runtime.dispose();
      },
      skip: 'net2025.cc returns an HTML challenge, no JSON API',
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'AllAnime video link (Cloudflare)',
      () async {
        final runtime = JsSourceRuntime(
          MSource(
            id: 1,
            name: 'AllAnime',
            baseUrl: 'https://allmanga.to',
            apiUrl: 'https://api.allanime.day/api',
            lang: 'en',
          ),
          fixture('allanime.js'),
          preferences: {
            'alt_hoster_selection1': ['player'],
            'preferred_sub': 'sub',
            'preferred_title_style': 'eng',
          },
        );
        final pages = await runtime.getPopular(1);
        expect(pages.list, isNotEmpty);
        runtime.dispose();
      },
      skip: 'api.allanime.day returns a Cloudflare challenge',
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'TioAnime video link (extractor globals)',
      () async {
        final runtime = JsSourceRuntime(
          MSource(
            id: 1,
            name: 'TioAnime',
            baseUrl: 'https://tioanime.com',
            lang: 'es',
          ),
          fixture('tioanime.js'),
        );
        final pages = await runtime.getPopular(1);
        expect(pages.list, isNotEmpty);
        runtime.dispose();
      },
      skip: 'requires Mangayomi host-extractor globals',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, skip: !runLive);

  group('dart sources', () {
    test('KissKh popular', () async {
      final runtime = DartSourceRuntime(
        MSource(
          id: 1,
          name: 'KissKh',
          baseUrl: 'https://kisskh.co',
          lang: 'en',
        ),
        fixture('kisskh.dart'),
      );
      final pages = await runtime.getPopular(1);
      expect(pages.list, isNotEmpty);
      expect(pages.list.first.name, isNotEmpty);
      final detail = await runtime.getDetail(pages.list.first.link!);
      expect(detail.chapters, isNotEmpty);
      final videos = await runtime.getVideoList(detail.chapters!.first.url!);
      expect(videos, isNotEmpty);
      expect(videos.first.url, startsWith('http'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('MangaHere manga pages', () async {
      final runtime = DartSourceRuntime(
        MSource(
          id: 1,
          name: 'MangaHere',
          baseUrl: 'https://mangahere.cc',
          lang: 'en',
        ),
        fixture('mangahere.dart'),
      );
      final pages = await runtime.getPopular(1);
      expect(pages.list, isNotEmpty);
      final detail = await runtime.getDetail(pages.list.first.link!);
      expect(detail.chapters, isNotEmpty);
      final pageList = await runtime.getPageList(detail.chapters!.first.url!);
      expect(pageList, isNotEmpty);
      expect(pageList.first.url, startsWith('http'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'Atsumaru popular (endpoint drift)',
      () async {
        final runtime = DartSourceRuntime(
          MSource(
            id: 1,
            name: 'Atsumaru',
            baseUrl: 'https://atsu.moe',
            apiUrl: 'https://atsu.moe',
            lang: 'en',
          ),
          fixture('atsumaru.dart'),
        );
        final pages = await runtime.getPopular(1);
        expect(pages.list, isNotEmpty);
      },
      skip: 'atsu.moe/filteredView returns 405 for the pinned source',
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'RoyalRoad popular (Cloudflare)',
      () async {
        final runtime = DartSourceRuntime(
          MSource(
            id: 1,
            name: 'RoyalRoad',
            baseUrl: 'https://royalroad.com',
            lang: 'en',
          ),
          fixture('royalroad.dart'),
        );
        final pages = await runtime.getPopular(1);
        expect(pages.list, isNotEmpty);
      },
      skip: 'royalroad.com returns a Cloudflare challenge',
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'AnimePahe video link (Cloudflare)',
      () async {
        final runtime = DartSourceRuntime(
          MSource(
            id: 1,
            name: 'AnimePahe',
            baseUrl: 'https://animepahe.su',
            lang: 'en',
          ),
          fixture('animepahe.dart'),
          preferences: {
            'preferred_domain_new2': 'https://animepahe.su',
            'preffered_link_type_1': false,
            'preferred_quality': '1080',
            'preferred_audio_1': 'jpn',
          },
        );
        final pages = await runtime.getPopular(1);
        expect(pages.list, isNotEmpty);
      },
      skip: 'animepahe.su returns an HTML challenge',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, skip: !runLive);
}
