library;

/// Where a Stremio stream entry points.
enum StremioStreamKind { direct, torrent, youtube, external, unsupported }

/// One resource the addon advertises (`catalog`, `meta`, `stream`, ...).
///
/// The addon protocol allows both string entries and objects with type/id
/// filters; both collapse into this shape.
class StremioResourceDescriptor {
  const StremioResourceDescriptor({
    required this.name,
    this.types = const [],
    this.idPrefixes = const [],
  });

  final String name;
  final List<String> types;
  final List<String> idPrefixes;

  bool acceptsType(String type) => types.isEmpty || types.contains(type);
  bool acceptsId(String id) =>
      idPrefixes.isEmpty || idPrefixes.any((p) => id.startsWith(p));
}

class StremioExtra {
  const StremioExtra({
    required this.name,
    this.isRequired = false,
    this.options = const [],
  });

  final String name;
  final bool isRequired;
  final List<String> options;
}

class StremioCatalog {
  const StremioCatalog({
    required this.type,
    required this.id,
    required this.name,
    this.extras = const [],
  });

  final String type;
  final String id;
  final String name;
  final List<StremioExtra> extras;

  bool supports(String extra) => extras.any((e) => e.name == extra);
  bool get isSearchable => supports('search');
  bool get isPaged => supports('skip');
}

class StremioManifest {
  const StremioManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.logo,
    this.resources = const [],
    this.types = const [],
    this.idPrefixes = const [],
    this.catalogs = const [],
    this.configurationUrl,
    this.configurable = false,
  });

  final String id;
  final String name;
  final String version;
  final String? description;
  final String? logo;
  final List<StremioResourceDescriptor> resources;
  final List<String> types;
  final List<String> idPrefixes;
  final List<StremioCatalog> catalogs;
  final Uri? configurationUrl;
  final bool configurable;

  bool supports(String resource) => resources.any((r) => r.name == resource);

  StremioResourceDescriptor? resource(String name) {
    for (final r in resources) {
      if (r.name == name) return r;
    }
    return null;
  }

  bool acceptsType(String type) =>
      types.isEmpty ||
      types.contains(type) ||
      resources.any((r) => r.acceptsType(type));

  bool acceptsId(String id) =>
      idPrefixes.isEmpty || idPrefixes.any((p) => id.startsWith(p));

  List<StremioCatalog> catalogsFor(String type) =>
      catalogs.where((c) => c.type == type).toList(growable: false);
}

class StremioMetaPreview {
  const StremioMetaPreview({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.releaseInfo,
    this.description,
  });

  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? releaseInfo;
  final String? description;
}

class StremioCatalogPage {
  const StremioCatalogPage({this.metas = const []});

  final List<StremioMetaPreview> metas;
}

class StremioVideo {
  const StremioVideo({
    required this.id,
    this.title,
    this.season,
    this.episode,
    this.thumbnail,
    this.overview,
    this.released,
    this.streams = const [],
  });

  final String id;
  final String? title;
  final int? season;
  final int? episode;
  final String? thumbnail;
  final String? overview;
  final String? released;
  final List<StremioStream> streams;
}

class StremioMeta {
  const StremioMeta({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.description,
    this.releaseInfo,
    this.imdbRating,
    this.runtime,
    this.genres = const [],
    this.videos = const [],
    this.defaultVideoId,
    this.externalIds = const {},
  });

  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? description;
  final String? releaseInfo;
  final String? imdbRating;
  final String? runtime;
  final List<String> genres;
  final List<StremioVideo> videos;
  final String? defaultVideoId;

  /// Verified id families only: `imdb`, `tmdb`, `kitsu`, `mal`.
  final Map<String, String> externalIds;

  String? externalId(String namespace) => externalIds[namespace];
}

class StremioSubtitle {
  const StremioSubtitle({
    required this.url,
    required this.lang,
    this.id,
    this.format,
  });

  final String url;
  final String lang;
  final String? id;
  final String? format;
}

class StremioStream {
  const StremioStream({
    required this.kind,
    this.url,
    this.infoHash,
    this.fileIndex,
    this.ytId,
    this.externalUrl,
    this.name,
    this.description,
    this.headers = const {},
    this.trackers = const [],
    this.fileName,
    this.bingeGroup,
    this.videoHash,
    this.videoSize,
    this.subtitles = const [],
  });

  final StremioStreamKind kind;

  /// Direct HTTP(S) URL. Null for torrent/youtube/external entries.
  final String? url;

  /// Normalized torrent info hash (lower-case hex or base32).
  final String? infoHash;

  /// The addon's explicit file choice; zero is a real value, never a default.
  final int? fileIndex;

  final String? ytId;
  final String? externalUrl;
  final String? name;
  final String? description;
  final Map<String, String> headers;
  final List<String> trackers;
  final String? fileName;
  /// Addon-supplied hint for matching this stream across episodes
  /// (`behaviorHints.bingeGroup`). Same group = same release family.
  final String? bingeGroup;
  final String? videoHash;
  final int? videoSize;
  final List<StremioSubtitle> subtitles;

  bool get isPlayable =>
      kind == StremioStreamKind.direct || kind == StremioStreamKind.torrent;
}

enum StremioFailureCategory {
  network,
  timeout,
  httpStatus,
  invalidJson,
  invalidResponse,
  invalidManifest,
  unsupportedScheme,
  tooManyRedirects,
  tooLarge,
}

/// Typed failure that never carries the configured URL, credentials or the
/// response body in its message.
class StremioFailure implements Exception {
  const StremioFailure(this.operation, this.category, {this.statusCode});

  final String operation;
  final StremioFailureCategory category;
  final int? statusCode;

  String get message {
    switch (category) {
      case StremioFailureCategory.network:
        return 'network error';
      case StremioFailureCategory.timeout:
        return 'timed out';
      case StremioFailureCategory.httpStatus:
        return 'HTTP ${statusCode ?? ''}'.trim();
      case StremioFailureCategory.invalidJson:
        return 'invalid JSON';
      case StremioFailureCategory.invalidResponse:
        return 'unexpected response';
      case StremioFailureCategory.invalidManifest:
        return 'invalid manifest';
      case StremioFailureCategory.unsupportedScheme:
        return 'unsupported URL scheme';
      case StremioFailureCategory.tooManyRedirects:
        return 'too many redirects';
      case StremioFailureCategory.tooLarge:
        return 'response too large';
    }
  }

  @override
  String toString() => 'Stremio $operation failed: $message';
}
