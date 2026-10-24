import 'dart:convert';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'crypto.dart';
import 'cloudflare_http.dart';
import 'html.dart';
import 'mangayomi_config.dart';
import 'models.dart';

const _bridgeLibrary = 'package:mangayomi/bridge_lib.dart';

class BridgeClient {
  BridgeClient([this.source])
    : _client = MangayomiHttpClient(protected: source?.hasCloudflare == true);

  final MSource? source;
  final http.Client _client;

  Future<http.Response> head(Uri url, {Map? headers}) =>
      _client.head(url, headers: _headers(headers));

  Future<http.Response> get(Uri url, {Map? headers}) =>
      _client.get(url, headers: _headers(headers));

  Future<http.Response> post(
    Uri url, {
    Map? headers,
    Object? body,
    Encoding? encoding,
  }) => _client.post(
    url,
    headers: _headers(headers),
    body: body,
    encoding: encoding,
  );

  Future<http.Response> put(
    Uri url, {
    Map? headers,
    Object? body,
    Encoding? encoding,
  }) => _client.put(
    url,
    headers: _headers(headers),
    body: body,
    encoding: encoding,
  );

  Future<http.Response> delete(
    Uri url, {
    Map? headers,
    Object? body,
    Encoding? encoding,
  }) => _client.delete(
    url,
    headers: _headers(headers),
    body: body,
    encoding: encoding,
  );

  Future<http.Response> patch(
    Uri url, {
    Map? headers,
    Object? body,
    Encoding? encoding,
  }) => _client.patch(
    url,
    headers: _headers(headers),
    body: body,
    encoding: encoding,
  );

  Future<String> read(Uri url, {Map? headers}) =>
      _client.read(url, headers: _headers(headers));

  void close() => _client.close();

  Map<String, String> _headers(Map? headers) {
    final result = <String, String>{
      if (headers != null)
        ...headers.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
    };
    result.putIfAbsent(
      HttpHeaders.userAgentHeader,
      () =>
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    );
    return result;
  }
}

class DartSourceRuntime {
  DartSourceRuntime(
    this.source,
    this.sourceCode, {
    Map<String, dynamic>? preferences,
  }) : preferences = Map.of(preferences ?? const {});

  final MSource source;
  final String sourceCode;
  final Map<String, dynamic> preferences;

  final D4rt _interpreter = D4rt();
  final List<BridgeClient> _clients = [];
  bool _initialized = false;
  bool _disposed = false;
  bool _defaultsSeeded = false;

  void init() {
    if (_disposed) throw StateError('Dart runtime has been disposed');
    if (_initialized) return;
    _registerBridge(_interpreter, source, preferences, _clients);
    _interpreter.execute(
      source: sourceCode.replaceAll('Client(source)', 'Client()'),
      positionalArgs: [source],
    );
    _initialized = true;
  }

  Future<T> invoke<T>(String method, [List<Object?> args = const []]) async {
    init();
    if (!_defaultsSeeded) {
      _defaultsSeeded = true;
      try {
        final declared = await _interpreter.invoke('getSourcePreferences', []);
        if (declared is List) {
          for (final item in declared) {
            final pref = preferenceMap(item);
            final key = pref['key'];
            if (key is String && pref['value'] != null) {
              preferences.putIfAbsent(key, () => pref['value']);
            }
          }
        }
      } catch (_) {
        // Sources without settings still run normally.
      }
    }
    final result = await _interpreter.invoke(method, args);
    if (result is T) return result;
    if (result is List && T == List<MVideo>) {
      return result.map((e) => e as MVideo).toList() as T;
    }
    if (result is List && T == List<String>) {
      return result.map((e) => e.toString()).toList() as T;
    }
    throw StateError('$method returned ${result.runtimeType}, expected $T');
  }

  Future<MPages> getPopular(int page) => invoke<MPages>('getPopular', [page]);

  Future<MPages> getLatestUpdates(int page) =>
      invoke<MPages>('getLatestUpdates', [page]);

  Future<MPages> search(
    String query,
    int page, [
    List<dynamic> filters = const [],
  ]) => invoke<MPages>('search', [query, page, FilterList(filters)]);

  Future<MManga> getDetail(String url) => invoke<MManga>('getDetail', [url]);

  Future<List<MVideo>> getVideoList(String url) =>
      invoke<List<MVideo>>('getVideoList', [url]);

  Future<List<MPage>> getPageList(String url) async {
    final pages = await invoke<List>('getPageList', [url]);
    return pages.map((page) {
      if (page is String) return MPage(page);
      if (page is Map && page['url'] is String) {
        return MPage(
          page['url'] as String,
          headers: _asStringMap(page['headers'] as Map?),
        );
      }
      throw const FormatException('Invalid manga page');
    }).toList();
  }

  Future<String> getHtmlContent(String name, String url) =>
      invoke<String>('getHtmlContent', [name, url]);

  Future<String> cleanHtmlContent(String html) =>
      invoke<String>('cleanHtmlContent', [html]);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }
}

void _registerBridge(
  D4rt interpreter,
  MSource source,
  Map<String, dynamic> preferences,
  List<BridgeClient> clients,
) {
  interpreter.registerBridgedEnum(
    BridgedEnumDefinition<MStatus>(name: 'MStatus', values: MStatus.values),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: MProviderBase,
      name: 'MProvider',
      constructors: {'': (_, _, _) => MProviderBase()},
      getters: {
        'supportsLatest': (_, target) =>
            (target as MProviderBase).supportsLatest,
        'baseUrl': (_, target) => (target as MProviderBase).baseUrl,
        'headers': (_, target) => (target as MProviderBase).headers,
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: MSource,
      name: 'MSource',
      constructors: {
        '': (_, positionalArgs, namedArgs) => MSource(
          id: namedArgs.get<int?>('id'),
          name: namedArgs.get<String?>('name'),
          baseUrl: namedArgs.get<String?>('baseUrl'),
          lang: namedArgs.get<String?>('lang'),
          isFullData: namedArgs.get<bool?>('isFullData'),
          hasCloudflare: namedArgs.get<bool?>('hasCloudflare'),
          dateFormat: namedArgs.get<String?>('dateFormat'),
          dateFormatLocale: namedArgs.get<String?>('dateFormatLocale'),
          apiUrl: namedArgs.get<String?>('apiUrl'),
          additionalParams: namedArgs.get<String?>('additionalParams'),
          notes: namedArgs.get<String?>('notes'),
        ),
      },
      getters: {
        'id': (_, target) => (target as MSource).id,
        'name': (_, target) => (target as MSource).name,
        'baseUrl': (_, target) => (target as MSource).baseUrl,
        'lang': (_, target) => (target as MSource).lang,
        'isFullData': (_, target) => (target as MSource).isFullData,
        'hasCloudflare': (_, target) => (target as MSource).hasCloudflare,
        'dateFormat': (_, target) => (target as MSource).dateFormat,
        'dateFormatLocale': (_, target) => (target as MSource).dateFormatLocale,
        'apiUrl': (_, target) => (target as MSource).apiUrl,
        'additionalParams': (_, target) => (target as MSource).additionalParams,
        'notes': (_, target) => (target as MSource).notes,
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: MManga,
      name: 'MManga',
      constructors: {
        '': (_, positionalArgs, namedArgs) {
          final manga = MManga(
            author: namedArgs.get<String?>('author'),
            artist: namedArgs.get<String?>('artist'),
            description: namedArgs.get<String?>('description'),
            genre: (namedArgs.get<List?>(
              'genre',
            ))?.map((e) => e.toString()).toList(),
            status: namedArgs.get<MStatus?>('status') ?? MStatus.unknown,
            imageUrl: namedArgs.get<String?>('imageUrl'),
            link: namedArgs.get<String?>('link'),
            chapters: _asList<MChapter>(namedArgs.get<List?>('chapters')),
            name: namedArgs.get<String?>('name'),
          );
          return manga;
        },
      },
      getters: {
        'name': (_, target) => (target as MManga).name,
        'artist': (_, target) => (target as MManga).artist,
        'author': (_, target) => (target as MManga).author,
        'description': (_, target) => (target as MManga).description,
        'genre': (_, target) => (target as MManga).genre,
        'status': (_, target) => (target as MManga).status,
        'imageUrl': (_, target) => (target as MManga).imageUrl,
        'link': (_, target) => (target as MManga).link,
        'chapters': (_, target) => (target as MManga).chapters,
      },
      setters: {
        'name': (_, target, value) =>
            (target as MManga).name = value as String?,
        'artist': (_, target, value) =>
            (target as MManga).artist = value as String?,
        'author': (_, target, value) =>
            (target as MManga).author = value as String?,
        'description': (_, target, value) =>
            (target as MManga).description = value as String?,
        'genre': (_, target, value) => (target as MManga).genre =
            (value as List?)?.map((e) => e.toString()).toList(),
        'status': (_, target, value) =>
            (target as MManga).status = value as MStatus?,
        'imageUrl': (_, target, value) =>
            (target as MManga).imageUrl = value as String?,
        'link': (_, target, value) =>
            (target as MManga).link = value as String?,
        'chapters': (_, target, value) =>
            (target as MManga).chapters = _asList<MChapter>(value as List?),
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: MChapter,
      name: 'MChapter',
      constructors: {
        '': (_, positionalArgs, namedArgs) => MChapter(
          name: namedArgs.get<String?>('name'),
          url: namedArgs.get<String?>('url'),
          dateUpload: namedArgs.get<String?>('dateUpload'),
          scanlator: namedArgs.get<String?>('scanlator'),
          isFiller: namedArgs.get<bool?>('isFiller'),
          thumbnailUrl: namedArgs.get<String?>('thumbnailUrl'),
          description: namedArgs.get<String?>('description'),
          downloadSize: namedArgs.get<String?>('downloadSize'),
          duration: namedArgs.get<String?>('duration'),
        ),
      },
      getters: {
        'name': (_, target) => (target as MChapter).name,
        'url': (_, target) => (target as MChapter).url,
        'dateUpload': (_, target) => (target as MChapter).dateUpload,
        'scanlator': (_, target) => (target as MChapter).scanlator,
        'isFiller': (_, target) => (target as MChapter).isFiller,
        'thumbnailUrl': (_, target) => (target as MChapter).thumbnailUrl,
        'description': (_, target) => (target as MChapter).description,
        'downloadSize': (_, target) => (target as MChapter).downloadSize,
        'duration': (_, target) => (target as MChapter).duration,
      },
      setters: {
        'name': (_, target, value) =>
            (target as MChapter).name = value as String?,
        'url': (_, target, value) =>
            (target as MChapter).url = value as String?,
        'dateUpload': (_, target, value) =>
            (target as MChapter).dateUpload = value as String?,
        'scanlator': (_, target, value) =>
            (target as MChapter).scanlator = value as String?,
        'isFiller': (_, target, value) =>
            (target as MChapter).isFiller = value as bool?,
        'thumbnailUrl': (_, target, value) =>
            (target as MChapter).thumbnailUrl = value as String?,
        'description': (_, target, value) =>
            (target as MChapter).description = value as String?,
        'downloadSize': (_, target, value) =>
            (target as MChapter).downloadSize = value as String?,
        'duration': (_, target, value) =>
            (target as MChapter).duration = value as String?,
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: MPages,
      name: 'MPages',
      constructors: {
        '': (_, positionalArgs, namedArgs) => MPages(
          list: _asList<MManga>(positionalArgs[0] as List?) ?? [],
          hasNextPage: positionalArgs.length > 1
              ? positionalArgs[1] as bool
              : false,
        ),
      },
      getters: {
        'list': (_, target) => (target as MPages).list,
        'hasNextPage': (_, target) => (target as MPages).hasNextPage,
      },
      setters: {
        'list': (_, target, value) =>
            (target as MPages).list = _asList<MManga>(value as List?) ?? [],
        'hasNextPage': (_, target, value) =>
            (target as MPages).hasNextPage = value as bool,
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: Track,
      name: 'MTrack',
      constructors: {
        '': (_, positionalArgs, namedArgs) => Track(
          file: namedArgs.get<String?>('file'),
          label: namedArgs.get<String?>('label'),
        ),
      },
      getters: {
        'file': (_, target) => (target as Track).file,
        'label': (_, target) => (target as Track).label,
      },
      setters: {
        'file': (_, target, value) => (target as Track).file = value as String?,
        'label': (_, target, value) =>
            (target as Track).label = value as String?,
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: MVideo,
      name: 'MVideo',
      constructors: {
        '': (_, positionalArgs, namedArgs) => MVideo(
          positionalArgs.get<String?>(0) ?? '',
          positionalArgs.get<String?>(1) ?? '',
          positionalArgs.get<String?>(2) ?? '',
          headers: _asStringMap(namedArgs.get<Map?>('headers')),
          subtitles: _asList<Track>(namedArgs.get<List?>('subtitles')),
          audios: _asList<Track>(namedArgs.get<List?>('audios')),
        ),
      },
      getters: {
        'url': (_, target) => (target as MVideo).url,
        'quality': (_, target) => (target as MVideo).quality,
        'originalUrl': (_, target) => (target as MVideo).originalUrl,
        'headers': (_, target) => (target as MVideo).headers,
        'subtitles': (_, target) => (target as MVideo).subtitles,
        'audios': (_, target) => (target as MVideo).audios,
      },
      setters: {
        'url': (_, target, value) => (target as MVideo).url = value as String,
        'quality': (_, target, value) =>
            (target as MVideo).quality = value as String,
        'originalUrl': (_, target, value) =>
            (target as MVideo).originalUrl = value as String,
        'headers': (_, target, value) =>
            (target as MVideo).headers = _asStringMap(value as Map?),
        'subtitles': (_, target, value) =>
            (target as MVideo).subtitles = _asList<Track>(value as List?),
        'audios': (_, target, value) =>
            (target as MVideo).audios = _asList<Track>(value as List?),
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: BridgeClient,
      name: 'Client',
      constructors: {
        '': (_, positionalArgs, namedArgs) {
          final client = BridgeClient(
            positionalArgs.isNotEmpty ? positionalArgs[0] as MSource : source,
          );
          clients.add(client);
          return client;
        },
      },
      methods: {
        'get': (_, target, positionalArgs, namedArgs) =>
            (target as BridgeClient).get(
              positionalArgs[0] as Uri,
              headers: namedArgs.get<Map?>('headers'),
            ),
        'post': (_, target, positionalArgs, namedArgs) =>
            (target as BridgeClient).post(
              positionalArgs[0] as Uri,
              headers: namedArgs.get<Map?>('headers'),
              body: namedArgs.get<Object?>('body'),
              encoding: namedArgs.get<Encoding?>('encoding'),
            ),
        'put': (_, target, positionalArgs, namedArgs) =>
            (target as BridgeClient).put(
              positionalArgs[0] as Uri,
              headers: namedArgs.get<Map?>('headers'),
              body: namedArgs.get<Object?>('body'),
              encoding: namedArgs.get<Encoding?>('encoding'),
            ),
        'delete': (_, target, positionalArgs, namedArgs) =>
            (target as BridgeClient).delete(
              positionalArgs[0] as Uri,
              headers: namedArgs.get<Map?>('headers'),
              body: namedArgs.get<Object?>('body'),
              encoding: namedArgs.get<Encoding?>('encoding'),
            ),
        'head': (_, target, positionalArgs, namedArgs) =>
            (target as BridgeClient).head(
              positionalArgs[0] as Uri,
              headers: namedArgs.get<Map?>('headers'),
            ),
        'patch': (_, target, positionalArgs, namedArgs) =>
            (target as BridgeClient).patch(
              positionalArgs[0] as Uri,
              headers: namedArgs.get<Map?>('headers'),
              body: namedArgs.get<Object?>('body'),
              encoding: namedArgs.get<Encoding?>('encoding'),
            ),
        'read': (_, target, positionalArgs, namedArgs) =>
            (target as BridgeClient).read(
              positionalArgs[0] as Uri,
              headers: namedArgs.get<Map?>('headers'),
            ),
        'close': (_, target, positionalArgs, namedArgs) =>
            (target as BridgeClient).close(),
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: http.Response,
      name: 'Response',
      getters: {
        'statusCode': (_, target) => (target as http.Response).statusCode,
        'body': (_, target) => (target as http.Response).body,
        'headers': (_, target) => (target as http.Response).headers,
        'isRedirect': (_, target) => (target as http.Response).isRedirect,
        'reasonPhrase': (_, target) => (target as http.Response).reasonPhrase,
        'contentLength': (_, target) => (target as http.Response).contentLength,
        'bodyBytes': (_, target) => (target as http.Response).bodyBytes,
        'persistentConnection': (_, target) =>
            (target as http.Response).persistentConnection,
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: MDocument,
      name: 'MDocument',
      constructors: {
        '': (_, positionalArgs, namedArgs) =>
            MDocument(html_parser.parse(positionalArgs[0] as String)),
      },
      getters: {
        'body': (_, target) => (target as MDocument).body,
        'documentElement': (_, target) => (target as MDocument).documentElement,
        'head': (_, target) => (target as MDocument).head,
        'parent': (_, target) => (target as MDocument).parent,
        'outerHtml': (_, target) => (target as MDocument).outerHtml,
        'text': (_, target) => (target as MDocument).text,
        'children': (_, target) => (target as MDocument).children,
      },
      methods: {
        'select': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).select(positionalArgs[0] as String),
        'selectFirst': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).selectFirst(positionalArgs[0] as String),
        'getElementsByClassName': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).getElementsByClassName(
              positionalArgs[0] as String,
            ),
        'getElementsByTagName': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).getElementsByTagName(
              positionalArgs[0] as String,
            ),
        'getElementById': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).getElementById(positionalArgs[0] as String),
        'attr': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).attr(positionalArgs[0] as String),
        'hasAttr': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).hasAttr(positionalArgs[0] as String),
        'xpath': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).xpath(positionalArgs[0] as String),
        'xpathFirst': (_, target, positionalArgs, namedArgs) =>
            (target as MDocument).xpathFirst(positionalArgs[0] as String),
      },
    ),
    _bridgeLibrary,
  );

  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: MElement,
      name: 'MElement',
      getters: {
        'outerHtml': (_, target) => (target as MElement).outerHtml,
        'innerHtml': (_, target) => (target as MElement).innerHtml,
        'text': (_, target) => (target as MElement).text,
        'className': (_, target) => (target as MElement).className,
        'localName': (_, target) => (target as MElement).localName,
        'namespaceUri': (_, target) => (target as MElement).namespaceUri,
        'getSrc': (_, target) => (target as MElement).getSrc,
        'getImg': (_, target) => (target as MElement).getImg,
        'getHref': (_, target) => (target as MElement).getHref,
        'getDataSrc': (_, target) => (target as MElement).getDataSrc,
        'children': (_, target) => (target as MElement).children,
        'parent': (_, target) => (target as MElement).parent,
        'nextElementSibling': (_, target) =>
            (target as MElement).nextElementSibling,
        'previousElementSibling': (_, target) =>
            (target as MElement).previousElementSibling,
      },
      methods: {
        'attr': (_, target, positionalArgs, namedArgs) =>
            (target as MElement).attr(positionalArgs[0] as String),
        'select': (_, target, positionalArgs, namedArgs) =>
            (target as MElement).select(positionalArgs[0] as String),
        'selectFirst': (_, target, positionalArgs, namedArgs) =>
            (target as MElement).selectFirst(positionalArgs[0] as String),
        'getElementsByClassName': (_, target, positionalArgs, namedArgs) =>
            (target as MElement).getElementsByClassName(
              positionalArgs[0] as String,
            ),
        'getElementsByTagName': (_, target, positionalArgs, namedArgs) =>
            (target as MElement).getElementsByTagName(
              positionalArgs[0] as String,
            ),
        'xpath': (_, target, positionalArgs, namedArgs) =>
            (target as MElement).xpath(positionalArgs[0] as String),
        'xpathFirst': (_, target, positionalArgs, namedArgs) =>
            (target as MElement).xpathFirst(positionalArgs[0] as String),
        'hasAttr': (_, target, positionalArgs, namedArgs) =>
            (target as MElement).hasAttr(positionalArgs[0] as String),
      },
    ),
    _bridgeLibrary,
  );

  _registerFilters(interpreter);
  _registerPreferences(interpreter);
  _registerFunctions(interpreter, preferences);
}

void _registerPreferences(D4rt interpreter) {
  void register(BridgedClass bridged) =>
      interpreter.registerBridgedClass(bridged, _bridgeLibrary);

  register(
    BridgedClass(
      nativeType: ListPreference,
      name: 'ListPreference',
      constructors: {
        '': (_, p, n) => ListPreference(
          key: n.get<String?>('key'),
          title: n.get<String?>('title'),
          summary: n.get<String?>('summary'),
          valueIndex: n.get<int?>('valueIndex'),
          entries: (n.get<List?>('entries'))?.cast<String>(),
          entryValues: (n.get<List?>('entryValues'))?.cast<String>(),
        ),
      },
    ),
  );
  register(
    BridgedClass(
      nativeType: EditTextPreference,
      name: 'EditTextPreference',
      constructors: {
        '': (_, p, n) => EditTextPreference(
          key: n.get<String?>('key'),
          title: n.get<String?>('title'),
          summary: n.get<String?>('summary'),
          value: n.get<String?>('value'),
        ),
      },
    ),
  );
  register(
    BridgedClass(
      nativeType: SwitchPreferenceCompat,
      name: 'SwitchPreferenceCompat',
      constructors: {
        '': (_, p, n) => SwitchPreferenceCompat(
          key: n.get<String?>('key'),
          title: n.get<String?>('title'),
          summary: n.get<String?>('summary'),
          value: n.get<bool?>('value'),
        ),
      },
    ),
  );
  register(
    BridgedClass(
      nativeType: CheckBoxPreference,
      name: 'CheckBoxPreference',
      constructors: {
        '': (_, p, n) => CheckBoxPreference(
          key: n.get<String?>('key'),
          title: n.get<String?>('title'),
          summary: n.get<String?>('summary'),
          value: n.get<bool?>('value'),
        ),
      },
    ),
  );
  register(
    BridgedClass(
      nativeType: MultiSelectListPreference,
      name: 'MultiSelectListPreference',
      constructors: {
        '': (_, p, n) => MultiSelectListPreference(
          key: n.get<String?>('key'),
          title: n.get<String?>('title'),
          summary: n.get<String?>('summary'),
          entries: (n.get<List?>('entries'))?.cast<String>(),
          entryValues: (n.get<List?>('entryValues'))?.cast<String>(),
          values: (n.get<List?>('values'))?.cast<String>(),
        ),
      },
    ),
  );
}

void _registerFilters(D4rt interpreter) {
  void register(BridgedClass bridged) =>
      interpreter.registerBridgedClass(bridged, _bridgeLibrary);

  register(
    BridgedClass(
      nativeType: FilterList,
      name: 'FilterList',
      constructors: {
        '': (_, positionalArgs, namedArgs) =>
            FilterList(positionalArgs[0] as List),
      },
      getters: {'filters': (_, target) => (target as FilterList).filters},
      setters: {
        'filters': (_, target, value) =>
            (target as FilterList).filters = value as List,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: SelectFilter,
      name: 'SelectFilter',
      constructors: {
        '': (_, p, n) => SelectFilter(
          p.get<String?>(0),
          p.get<String>(1) ?? '',
          p.get<int>(2) ?? 0,
          p.get<List>(3) ?? [],
          p.get<String?>(4),
        ),
      },
      getters: {
        'type': (_, target) => (target as SelectFilter).type,
        'name': (_, target) => (target as SelectFilter).name,
        'state': (_, target) => (target as SelectFilter).state,
        'values': (_, target) => (target as SelectFilter).values,
        'typeName': (_, target) => (target as SelectFilter).typeName,
      },
      setters: {
        'state': (_, target, value) =>
            (target as SelectFilter).state = value as int,
        'values': (_, target, value) =>
            (target as SelectFilter).values = value as List,
        'type': (_, target, value) =>
            (target as SelectFilter).type = value as String?,
        'name': (_, target, value) =>
            (target as SelectFilter).name = value as String,
        'typeName': (_, target, value) =>
            (target as SelectFilter).typeName = value as String?,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: SelectFilterOption,
      name: 'SelectFilterOption',
      constructors: {
        '': (_, p, n) => SelectFilterOption(
          p.get<String>(0) ?? '',
          p.get<String>(1) ?? '',
          p.get<String?>(2),
        ),
      },
      getters: {
        'name': (_, target) => (target as SelectFilterOption).name,
        'value': (_, target) => (target as SelectFilterOption).value,
        'typeName': (_, target) => (target as SelectFilterOption).typeName,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: SeparatorFilter,
      name: 'SeparatorFilter',
      constructors: {
        '': (_, p, n) =>
            SeparatorFilter(p.get<String?>(0), p.get<String?>(1) ?? ''),
      },
      getters: {
        'type': (_, target) => (target as SeparatorFilter).type,
        'typeName': (_, target) => (target as SeparatorFilter).typeName,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: HeaderFilter,
      name: 'HeaderFilter',
      constructors: {
        '': (_, p, n) => HeaderFilter(
          p.get<String>(0) ?? '',
          p.get<String?>(1),
          p.get<String?>(2) ?? '',
        ),
      },
      getters: {
        'type': (_, target) => (target as HeaderFilter).type,
        'name': (_, target) => (target as HeaderFilter).name,
        'typeName': (_, target) => (target as HeaderFilter).typeName,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: TextFilter,
      name: 'TextFilter',
      constructors: {
        '': (_, p, n) => TextFilter(
          p.get<String?>(0),
          p.get<String>(1) ?? '',
          p.get<String?>(2),
          p.get<String?>(3) ?? '',
        ),
      },
      getters: {
        'type': (_, target) => (target as TextFilter).type,
        'name': (_, target) => (target as TextFilter).name,
        'state': (_, target) => (target as TextFilter).state,
        'typeName': (_, target) => (target as TextFilter).typeName,
      },
      setters: {
        'state': (_, target, value) =>
            (target as TextFilter).state = value as String,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: SortState,
      name: 'SortState',
      constructors: {
        '': (_, p, n) => SortState(
          p.get<int>(0) ?? 0,
          p.get<bool>(1) ?? false,
          p.get<String?>(2),
        ),
      },
      getters: {
        'index': (_, target) => (target as SortState).index,
        'ascending': (_, target) => (target as SortState).ascending,
        'typeName': (_, target) => (target as SortState).typeName,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: SortFilter,
      name: 'SortFilter',
      constructors: {
        '': (_, p, n) => SortFilter(
          p.get<String?>(0),
          p.get<String>(1) ?? '',
          p.get<SortState>(2) ?? SortState(0, false),
          p.get<List>(3) ?? [],
          p.get<String?>(4),
        ),
      },
      getters: {
        'type': (_, target) => (target as SortFilter).type,
        'name': (_, target) => (target as SortFilter).name,
        'state': (_, target) => (target as SortFilter).state,
        'values': (_, target) => (target as SortFilter).values,
        'typeName': (_, target) => (target as SortFilter).typeName,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: TriStateFilter,
      name: 'TriStateFilter',
      constructors: {
        '': (_, p, n) => TriStateFilter(
          p.get<String>(0) ?? '',
          p.get<String>(1) ?? '',
          p.get<String?>(2),
          p.get<String?>(3),
          p.get<int?>(3) ?? 0,
        ),
      },
      getters: {
        'type': (_, target) => (target as TriStateFilter).type,
        'name': (_, target) => (target as TriStateFilter).name,
        'value': (_, target) => (target as TriStateFilter).value,
        'state': (_, target) => (target as TriStateFilter).state,
        'typeName': (_, target) => (target as TriStateFilter).typeName,
      },
      setters: {
        'state': (_, target, value) =>
            (target as TriStateFilter).state = value as int,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: GroupFilter,
      name: 'GroupFilter',
      constructors: {
        '': (_, p, n) => GroupFilter(
          p.get<String?>(0),
          p.get<String>(1) ?? '',
          p.get<List>(2) ?? [],
          p.get<String?>(3),
        ),
      },
      getters: {
        'type': (_, target) => (target as GroupFilter).type,
        'name': (_, target) => (target as GroupFilter).name,
        'state': (_, target) => (target as GroupFilter).state,
        'typeName': (_, target) => (target as GroupFilter).typeName,
      },
    ),
  );

  register(
    BridgedClass(
      nativeType: CheckBoxFilter,
      name: 'CheckBoxFilter',
      constructors: {
        '': (_, p, n) => CheckBoxFilter(
          p.get<String>(0) ?? '',
          p.get<String>(1) ?? '',
          p.get<String?>(2),
          p.get<bool?>(3) ?? false,
          p.get<String?>(4),
        ),
      },
      getters: {
        'type': (_, target) => (target as CheckBoxFilter).type,
        'name': (_, target) => (target as CheckBoxFilter).name,
        'value': (_, target) => (target as CheckBoxFilter).value,
        'state': (_, target) => (target as CheckBoxFilter).state,
        'typeName': (_, target) => (target as CheckBoxFilter).typeName,
      },
    ),
  );
}

void _registerFunctions(D4rt interpreter, Map<String, dynamic> preferences) {
  interpreter.registertopLevelFunction(
    'getPreferenceValue',
    (_, p, n, _) => preferences[p[1].toString()]?.toString() ?? '',
  );
  interpreter.registertopLevelFunction(
    'getPrefStringValue',
    (_, p, n, _) =>
        preferences[p[1].toString()]?.toString() ?? (p[2] as String? ?? ''),
  );
  interpreter.registertopLevelFunction(
    'cryptoHandler',
    (_, p, n, _) => Crypto.cryptoHandler(
      p[0] as String,
      p[1] as String,
      p[2] as String,
      p[3] as bool,
    ),
  );
  interpreter.registertopLevelFunction(
    'encryptAESCryptoJS',
    (_, p, n, _) => Crypto.encryptAESCryptoJS(p[0] as String, p[1] as String),
  );
  interpreter.registertopLevelFunction(
    'decryptAESCryptoJS',
    (_, p, n, _) => Crypto.decryptAESCryptoJS(p[0] as String, p[1] as String),
  );
  interpreter.registertopLevelFunction(
    'substringAfter',
    (_, p, n, _) => _substringAfter(p[0] as String, p[1] as String),
  );
  interpreter.registertopLevelFunction(
    'substringAfterLast',
    (_, p, n, _) => _substringAfterLast(p[0] as String, p[1] as String),
  );
  interpreter.registertopLevelFunction(
    'substringBefore',
    (_, p, n, _) => _substringBefore(p[0] as String, p[1] as String),
  );
  interpreter.registertopLevelFunction(
    'substringBeforeLast',
    (_, p, n, _) => _substringBeforeLast(p[0] as String, p[1] as String),
  );
  interpreter.registertopLevelFunction(
    'parseStatus',
    (_, p, n, _) => _parseStatus(p[0] as String, p[1] as List),
  );
  interpreter.registertopLevelFunction(
    'parseHtml',
    (_, p, n, _) => MDocument.parse(p[0] as String),
  );
  interpreter.registertopLevelFunction(
    'xpath',
    (_, p, n, _) => xpathOf(html_parser.parse(p[0] as String), p[1] as String),
  );
  interpreter.registertopLevelFunction('getMapValue', (_, p, n, _) {
    try {
      final map = jsonDecode(p[0] as String) as Map;
      final value = map[p[1]];
      return (n.get<bool?>('encode') ?? false)
          ? jsonEncode(value)
          : value?.toString() ?? '';
    } catch (_) {
      return '';
    }
  });
  interpreter.registertopLevelFunction('print', (_, p, n, _) {
    // ignore: avoid_print
    print(p.isNotEmpty ? p[0] : '');
    return null;
  });
}

String _substringAfter(String text, String pattern) {
  final index = text.indexOf(pattern);
  return index == -1 ? text : text.substring(index + pattern.length);
}

String _substringAfterLast(String text, String pattern) =>
    text.split(pattern).last;

String _substringBefore(String text, String pattern) {
  final index = text.indexOf(pattern);
  return index == -1 ? text : text.substring(0, index);
}

String _substringBeforeLast(String text, String pattern) {
  final index = text.lastIndexOf(pattern);
  return index == -1 ? text : text.substring(0, index);
}

MStatus _parseStatus(String status, List statusList) {
  for (final element in statusList) {
    if (element is! Map) continue;
    for (final entry in element.entries) {
      if (entry.key.toString().toLowerCase().contains(
        status.toLowerCase().trim(),
      )) {
        return switch (entry.value as int) {
          0 => MStatus.ongoing,
          1 => MStatus.completed,
          2 => MStatus.onHiatus,
          3 => MStatus.canceled,
          4 => MStatus.publishingFinished,
          _ => MStatus.unknown,
        };
      }
    }
  }
  return MStatus.unknown;
}

List<T>? _asList<T>(List? value) {
  if (value == null) return null;
  return value.map((e) => e as T).toList();
}

Map<String, String>? _asStringMap(Map? value) {
  if (value == null) return null;
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}
