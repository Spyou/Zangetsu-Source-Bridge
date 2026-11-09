library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Stateless Stremio addon protocol client.
///
/// It knows HTTP only: no Hive, no app sources, no schedulers or caches. Each
/// call takes the configured transport base URI (the addon URL without
/// `/manifest.json`) and the original protocol arguments.
class StremioClient {
  StremioClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 12),
    this.allowHttp = false,
    this.maxRedirects = 5,
    this.maxJsonBytes = 5 * 1024 * 1024,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;
  final bool allowHttp;
  final int maxRedirects;
  final int maxJsonBytes;

  void close() => _http.close();

  Future<StremioManifest> manifest(Uri base) async {
    final json = await _getJson(
      _join(base, [_enc('manifest.json')]),
      'manifest',
    );
    return _parseManifest(json, base);
  }

  Future<StremioCatalogPage> catalog(
    Uri base, {
    required String type,
    required String catalogId,
    String? search,
    int? skip,
    String? genre,
  }) async {
    final extras = <String, String>{};
    if (search != null && search.isNotEmpty) extras['search'] = search;
    if (skip != null && skip > 0) extras['skip'] = '$skip';
    if (genre != null && genre.isNotEmpty) extras['genre'] = genre;

    final parts = <String>[_enc('catalog'), _enc(type)];
    if (extras.isEmpty) {
      parts.add('${_enc(catalogId)}.json');
    } else {
      parts.add(_enc(catalogId));
      parts.add(_extras(extras));
    }
    final json = await _getJson(_join(base, parts), 'catalog');
    final metas = json['metas'];
    if (metas is! List) {
      throw const StremioFailure(
        'catalog',
        StremioFailureCategory.invalidResponse,
      );
    }
    final items = <StremioMetaPreview>[];
    for (final raw in metas) {
      if (raw is! Map) continue;
      final id = _str(raw['id']);
      final name = _str(raw['name']);
      if (id == null || name == null) continue;
      items.add(
        StremioMetaPreview(
          id: id,
          type: _str(raw['type']) ?? type,
          name: name,
          poster: _str(raw['poster']),
          background: _str(raw['background']),
          logo: _str(raw['logo']),
          releaseInfo: _str(raw['releaseInfo']),
          description: _str(raw['description']),
        ),
      );
    }
    return StremioCatalogPage(metas: items);
  }

  Future<StremioMeta?> meta(
    Uri base, {
    required String type,
    required String id,
  }) async {
    final json = await _getJson(
      _join(base, [_enc('meta'), _enc(type), '${_enc(id)}.json']),
      'meta',
    );
    final raw = json['meta'];
    if (raw == null) return null;
    if (raw is! Map) {
      throw const StremioFailure(
        'meta',
        StremioFailureCategory.invalidResponse,
      );
    }
    final metaId = _str(raw['id']);
    if (metaId == null) {
      throw const StremioFailure(
        'meta',
        StremioFailureCategory.invalidResponse,
      );
    }
    final videos = <StremioVideo>[];
    final rawVideos = raw['videos'];
    if (rawVideos is List) {
      for (final v in rawVideos) {
        if (v is! Map) continue;
        final videoId = _str(v['id']);
        if (videoId == null) continue;
        videos.add(
          StremioVideo(
            id: videoId,
            title: _str(v['title']) ?? _str(v['name']),
            season: _int(v['season']),
            episode: _int(v['episode']),
            thumbnail: _str(v['thumbnail']),
            overview: _str(v['overview']),
            released: _str(v['released']) ?? _str(v['releaseInfo']),
            streams: _parseStreams(v['streams']),
          ),
        );
      }
    }
    return StremioMeta(
      id: metaId,
      type: _str(raw['type']) ?? type,
      name: _str(raw['name']) ?? metaId,
      poster: _str(raw['poster']),
      background: _str(raw['background']),
      logo: _str(raw['logo']),
      description: _str(raw['description']),
      releaseInfo: _str(raw['releaseInfo']),
      imdbRating: _str(raw['imdbRating']),
      runtime: _str(raw['runtime']),
      genres: _strings(raw['genres']),
      videos: videos,
      defaultVideoId: _str(raw['defaultVideoId']),
      externalIds: _externalIds(raw, metaId),
    );
  }

  Future<List<StremioStream>> streams(
    Uri base, {
    required String type,
    required String id,
  }) async {
    final json = await _getJson(
      _join(base, [_enc('stream'), _enc(type), '${_enc(id)}.json']),
      'streams',
    );
    final raw = json['streams'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw const StremioFailure(
        'streams',
        StremioFailureCategory.invalidResponse,
      );
    }
    return _parseStreams(raw);
  }

  Future<List<StremioSubtitle>> subtitles(
    Uri base, {
    required String type,
    required String id,
    String? filename,
    String? videoHash,
    int? videoSize,
  }) async {
    final extras = <String, String>{};
    if (filename != null && filename.isNotEmpty) {
      extras['filename'] = filename;
    }
    if (videoHash != null && videoHash.isNotEmpty) {
      extras['videoHash'] = videoHash;
    }
    if (videoSize != null && videoSize > 0) {
      extras['videoSize'] = '$videoSize';
    }
    final parts = <String>[_enc('subtitles'), _enc(type)];
    if (extras.isEmpty) {
      parts.add('${_enc(id)}.json');
    } else {
      parts.add(_enc(id));
      parts.add(_extras(extras));
    }
    final json = await _getJson(_join(base, parts), 'subtitles');
    final raw = json['subtitles'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw const StremioFailure(
        'subtitles',
        StremioFailureCategory.invalidResponse,
      );
    }
    return _parseSubtitles(raw);
  }

  // ---------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> _getJson(Uri url, String operation) async {
    _checkScheme(url, operation);
    var uri = url;
    var redirects = 0;
    while (true) {
      final request = http.Request('GET', uri)..followRedirects = false;
      try {
        final response = await _http.send(request).timeout(timeout);
        if (_isRedirect(response.statusCode)) {
          final location =
              response.headers['location'] ?? response.headers['Location'];
          await response.stream.listen((_) {}).cancel().timeout(timeout);
          if (location == null || redirects >= maxRedirects) {
            throw StremioFailure(
              operation,
              StremioFailureCategory.tooManyRedirects,
            );
          }
          redirects++;
          final next = uri.resolve(location);
          _checkScheme(next, operation);
          uri = next;
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.listen((_) {}).cancel().timeout(timeout);
          throw StremioFailure(
            operation,
            StremioFailureCategory.httpStatus,
            statusCode: response.statusCode,
          );
        }
        final bytes = await _readBounded(response.stream, operation);
        final Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        } on FormatException {
          throw StremioFailure(operation, StremioFailureCategory.invalidJson);
        }
        if (decoded is! Map) {
          throw StremioFailure(
            operation,
            StremioFailureCategory.invalidResponse,
          );
        }
        return Map<String, dynamic>.from(decoded);
      } on StremioFailure {
        rethrow;
      } on TimeoutException {
        throw StremioFailure(operation, StremioFailureCategory.timeout);
      } catch (_) {
        throw StremioFailure(operation, StremioFailureCategory.network);
      }
    }
  }

  Future<List<int>> _readBounded(
    Stream<List<int>> stream,
    String operation,
  ) async {
    final builder = BytesBuilder(copy: false);
    final result = Completer<List<int>>();
    final timer = Timer(timeout, () {
      if (!result.isCompleted) {
        result.completeError(TimeoutException('response body'));
      }
    });
    final subscription = stream.listen(
      (chunk) {
        if (result.isCompleted) return;
        if (builder.length + chunk.length > maxJsonBytes) {
          result.completeError(
            StremioFailure(operation, StremioFailureCategory.tooLarge),
          );
        } else {
          builder.add(chunk);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
      onDone: () {
        if (!result.isCompleted) result.complete(builder.takeBytes());
      },
    );
    try {
      return await result.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  void _checkScheme(Uri uri, String operation) {
    if (uri.scheme == 'https') return;
    if (allowHttp && uri.scheme == 'http') return;
    throw StremioFailure(operation, StremioFailureCategory.unsupportedScheme);
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  /// Builds an addon URL while keeping the configured base path and query.
  Uri _join(Uri base, List<String> encodedSegments) {
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final path = '$basePath/${encodedSegments.join('/')}';
    final origin = Uri(
      scheme: base.scheme,
      userInfo: base.userInfo.isEmpty ? null : base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
    ).toString();
    final query = base.hasQuery ? '?${base.query}' : '';
    return Uri.parse('$origin$path$query');
  }

  static String _enc(String value) => Uri.encodeComponent(value);

  static String _extras(Map<String, String> extras) {
    final parts = extras.entries
        .map((e) => '${_enc(e.key)}=${_enc(e.value)}')
        .join('&');
    return '$parts.json';
  }

  // ---------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------

  StremioManifest _parseManifest(Map<String, dynamic> json, Uri base) {
    final id = _str(json['id']);
    if (id == null) {
      throw const StremioFailure(
        'manifest',
        StremioFailureCategory.invalidManifest,
      );
    }
    final resources = <StremioResourceDescriptor>[];
    final rawResources = json['resources'];
    if (rawResources is List) {
      for (final r in rawResources) {
        if (r is String) {
          resources.add(StremioResourceDescriptor(name: r));
        } else if (r is Map) {
          final name = _str(r['name']);
          if (name == null) continue;
          resources.add(
            StremioResourceDescriptor(
              name: name,
              types: _strings(r['types']),
              idPrefixes: _strings(r['idPrefixes']),
            ),
          );
        }
      }
    }

    final catalogs = <StremioCatalog>[];
    final rawCatalogs = json['catalogs'];
    if (rawCatalogs is List) {
      for (final c in rawCatalogs) {
        if (c is! Map) continue;
        final catalogType = _str(c['type']);
        final catalogId = _str(c['id']);
        if (catalogType == null || catalogId == null) continue;
        catalogs.add(
          StremioCatalog(
            type: catalogType,
            id: catalogId,
            name: _str(c['name']) ?? catalogId,
            extras: _parseExtras(c),
          ),
        );
      }
    }

    final hints = json['behaviorHints'];
    final hintMap = hints is Map ? hints : const {};
    final configuration = _str(hintMap['configurationURL']);
    Uri? configurationUrl;
    if (configuration != null && configuration.isNotEmpty) {
      configurationUrl = base.resolve(configuration);
    }

    return StremioManifest(
      id: id,
      name: _str(json['name']) ?? id,
      logo: _str(json['logo']) == null
          ? null
          : base.resolve(_str(json['logo'])!).toString(),
      version: _str(json['version']) ?? '0.0.0',
      description: _str(json['description']),
      resources: resources,
      types: _strings(json['types']),
      idPrefixes: _strings(json['idPrefixes']),
      catalogs: catalogs,
      configurationUrl: configurationUrl,
      configurable: hintMap['configurable'] == true,
    );
  }

  List<StremioExtra> _parseExtras(Map raw) {
    final found = <String, StremioExtra>{};
    final rawExtras = raw['extra'];
    if (rawExtras is List) {
      for (final e in rawExtras) {
        if (e is! Map) continue;
        final name = _str(e['name']);
        if (name == null) continue;
        found[name] = StremioExtra(
          name: name,
          isRequired: e['isRequired'] == true,
          options: _strings(e['options']),
        );
      }
    }
    for (final name in _strings(raw['extraSupported'])) {
      found.putIfAbsent(name, () => StremioExtra(name: name));
    }
    for (final name in _strings(raw['extraRequired'])) {
      final existing = found[name];
      found[name] = StremioExtra(
        name: name,
        isRequired: true,
        options: existing?.options ?? const [],
      );
    }
    return found.values.toList(growable: false);
  }

  List<StremioStream> _parseStreams(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) return const [];
    final out = <StremioStream>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      out.add(_parseStream(entry));
    }
    return out;
  }

  StremioStream _parseStream(Map raw) {
    final hints = raw['behaviorHints'];
    final hintMap = hints is Map ? hints : const {};
    final headers = <String, String>{};
    final proxy = hintMap['proxyHeaders'];
    if (proxy is Map) {
      final request = proxy['request'];
      if (request is Map) {
        for (final e in request.entries) {
          if (e.key is String && e.value is String) {
            headers[e.key as String] = e.value as String;
          }
        }
      }
    }

    final trackers = <String>[];
    final sources = raw['sources'];
    if (sources is List) {
      for (final s in sources) {
        if (s is! String) continue;
        if (s.startsWith('tracker:')) {
          final tracker = s.substring('tracker:'.length);
          if (_trackerUrl(tracker)) trackers.add(tracker);
        }
      }
    }

    final subtitles = _parseSubtitles(raw['subtitles']);
    final name = _str(raw['name']);
    final description = _str(raw['title']);
    final fileName = _str(hintMap['filename']);
    final videoHash = _str(hintMap['videoHash']);
    final videoSize = _int(hintMap['videoSize']);

    final url = _str(raw['url']);
    final rawHash = _str(raw['infoHash']);
    final ytId = _str(raw['ytId']);
    final externalUrl = _str(raw['externalUrl']);
    final rawFileIndex = raw['fileIdx'];
    var fileIndex = _int(rawFileIndex);
    final badFileIndex =
        rawFileIndex != null &&
        (fileIndex == null || fileIndex < 0 || fileIndex > 0x7fffffff);

    StremioStream base({
      required StremioStreamKind kind,
      String? directUrl,
      String? hash,
      List<String> extraTrackers = const [],
    }) => StremioStream(
      kind: kind,
      url: directUrl,
      infoHash: hash,
      fileIndex: fileIndex,
      ytId: ytId,
      externalUrl: externalUrl,
      name: name,
      description: description,
      headers: headers,
      trackers: [...trackers, ...extraTrackers],
      fileName: fileName,
      videoHash: videoHash,
      videoSize: videoSize,
      subtitles: subtitles,
    );

    if (url != null && url.startsWith('magnet:')) {
      final magnet = _parseMagnet(url);
      if (magnet == null || badFileIndex) {
        return base(kind: StremioStreamKind.unsupported);
      }
      fileIndex ??= magnet.fileIndex;
      return base(
        kind: StremioStreamKind.torrent,
        hash: magnet.hash,
        extraTrackers: magnet.trackers,
      );
    }
    if (rawHash != null && rawHash.isNotEmpty) {
      if (!_validHash(rawHash) || badFileIndex) {
        return base(kind: StremioStreamKind.unsupported);
      }
      return base(kind: StremioStreamKind.torrent, hash: rawHash.toLowerCase());
    }
    if (url != null && _httpUrl(url)) {
      return base(kind: StremioStreamKind.direct, directUrl: url);
    }
    if (ytId != null && ytId.isNotEmpty) {
      return base(kind: StremioStreamKind.youtube);
    }
    if (externalUrl != null && _httpUrl(externalUrl)) {
      return base(kind: StremioStreamKind.external);
    }
    return base(kind: StremioStreamKind.unsupported);
  }

  List<StremioSubtitle> _parseSubtitles(Object? raw) {
    if (raw is! List) return const [];
    final out = <StremioSubtitle>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final url = _str(entry['url']);
      final lang = _str(entry['lang']);
      if (url == null || lang == null || !_httpUrl(url)) continue;
      out.add(
        StremioSubtitle(
          id: _str(entry['id']),
          url: url,
          lang: lang,
          format: _formatOf(url),
        ),
      );
    }
    return out;
  }

  Map<String, String> _externalIds(Map raw, String id) {
    final ids = <String, String>{};
    void add(String namespace, String? value) {
      if (value == null || value.isEmpty) return;
      ids.putIfAbsent(namespace, () => value);
    }

    final imdb = _str(raw['imdb_id']) ?? _str(raw['imdbId']);
    if (imdb != null && RegExp(r'^tt\d+$').hasMatch(imdb)) add('imdb', imdb);
    final tmdb = _str(raw['moviedb_id']) ?? _str(raw['tmdb_id']);
    if (tmdb != null) add('tmdb', tmdb);
    final mal = _str(raw['mal_id']);
    if (mal != null) add('mal', mal);
    final kitsu = _str(raw['kitsu_id']);
    if (kitsu != null) add('kitsu', kitsu);

    if (RegExp(r'^tt\d+$').hasMatch(id)) add('imdb', id);
    final match = RegExp(r'^(tmdb|kitsu|mal):(\d+)$').firstMatch(id);
    if (match != null) add(match.group(1)!, match.group(2)!);

    return ids;
  }

  ({String hash, List<String> trackers, int? fileIndex})? _parseMagnet(
    String url,
  ) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    String? hash;
    final trackers = <String>[];
    for (final xt in uri.queryParametersAll['xt'] ?? const <String>[]) {
      final match = RegExp(r'^urn:btih:([A-Za-z0-9]+)$').firstMatch(xt);
      if (match != null && _validHash(match.group(1)!)) {
        hash = match.group(1)!.toLowerCase();
      }
    }
    for (final tr in uri.queryParametersAll['tr'] ?? const <String>[]) {
      if (_trackerUrl(tr)) trackers.add(tr);
    }
    if (hash == null) return null;
    final selected = uri.queryParametersAll['so'];
    final fileIndex = selected == null
        ? null
        : int.tryParse(selected.singleOrNull ?? '');
    if (selected != null &&
        (fileIndex == null || fileIndex < 0 || fileIndex > 0x7fffffff)) {
      return null;
    }
    return (hash: hash, trackers: trackers, fileIndex: fileIndex);
  }

  static bool _validHash(String value) =>
      RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(value) ||
      RegExp(r'^[A-Za-z2-7]{32}$').hasMatch(value);

  static bool _httpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static bool _trackerUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return const {'http', 'https', 'udp', 'ws', 'wss'}.contains(uri.scheme);
  }

  static String? _formatOf(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    return path.substring(dot + 1).toLowerCase();
  }

  static String? _str(Object? value) => value is String ? value : null;

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.truncateToDouble()) return value.toInt();
    return null;
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }
}
