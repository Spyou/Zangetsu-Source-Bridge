import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'mangayomi_repo.dart';
import 'mangayomi_source.dart';

class InstalledMangayomiSource {
  InstalledMangayomiSource(this.source, this.codeFile);

  final MangayomiSource source;
  final File codeFile;
}

class MangayomiExtensionService {
  MangayomiExtensionService(this.directory, {http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final Directory directory;
  final http.Client _client;
  final bool _ownsClient;
  Map<String, InstalledMangayomiSource>? _installed;
  List<Uri>? _repositories;

  Future<List<MangayomiSource>> fetchIndex(Uri url) async {
    if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const FormatException('Repository URL must use HTTPS');
    }
    final response = await _download(url, 5 * 1024 * 1024);
    return MangayomiRepository(url).parseIndex(utf8.decode(response));
  }

  Future<List<Uri>> repositories() async {
    if (_repositories == null) {
      await directory.create(recursive: true);
      final file = File(path.join(directory.path, 'repositories.json'));
      final entries = await file.exists()
          ? jsonDecode(await file.readAsString())
          : <Object>[];
      if (entries is! List || entries.any((entry) => entry is! String)) {
        throw const FormatException('Invalid repository list');
      }
      final seen = <Uri>{};
      _repositories = [
        for (final entry in entries)
          if (seen.add(_validateRepository(Uri.parse(entry))))
            _validateRepository(Uri.parse(entry)),
      ];
    }
    return List.unmodifiable(_repositories!);
  }

  Future<List<MangayomiSource>> addRepository(Uri url) async {
    url = _validateRepository(url);
    final sources = await refreshRepository(url);
    await repositories();
    if (!_repositories!.contains(url)) {
      _repositories!.add(url);
      try {
        await _saveRepositories();
      } catch (_) {
        _repositories!.remove(url);
        rethrow;
      }
    }
    return sources;
  }

  Future<void> removeRepository(Uri url) async {
    await repositories();
    if (!_repositories!.remove(url)) return;
    try {
      await _saveRepositories();
    } catch (_) {
      _repositories!.add(url);
      rethrow;
    }
  }

  Future<List<MangayomiSource>> refreshRepository(Uri url) async {
    url = _validateRepository(url);
    final indexes = url.path.endsWith('.json')
        ? [url]
        : [
            for (final name in [
              'index.json',
              'anime_index.json',
              'manga_index.json',
              'novel_index.json',
            ])
              url.replace(
                path:
                    '${url.path.endsWith('/') ? url.path : '${url.path}/'}$name',
              ),
          ];
    final sources = <String, MangayomiSource>{};
    var foundIndex = false;
    for (final index in indexes) {
      try {
        final entries = await fetchIndex(index);
        foundIndex = true;
        for (final source in entries) {
          // Repos overlap: index.json often repeats sources that also live in
          // the per-type index files. Identical repeats merge silently; a
          // genuinely different manifest under the same key is a broken repo.
          final existing = sources[source.key];
          if (existing == null) {
            sources[source.key] = source;
          } else if (jsonEncode(existing.toManifest()) !=
              jsonEncode(source.toManifest())) {
            throw FormatException('Conflicting source ${source.name}');
          }
        }
      } on HttpException catch (error) {
        if (error.message != 'Download failed (404)' || indexes.length == 1) {
          rethrow;
        }
      }
    }
    if (!foundIndex) throw const FormatException('No repository index found');
    return List.unmodifiable(sources.values);
  }

  Uri _validateRepository(Uri url) {
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.hasQuery) {
      throw const FormatException(
        'Repository URL must use HTTPS without credentials, query, or fragment',
      );
    }
    return url;
  }

  Future<void> _saveRepositories() async {
    final file = File(path.join(directory.path, 'repositories.json'));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(_repositories!.map((url) => url.toString()).toList()),
      flush: true,
    );
    await temp.rename(file.path);
  }

  Future<List<InstalledMangayomiSource>> installed() async {
    await _load();
    return List.unmodifiable(_installed!.values);
  }

  Future<InstalledMangayomiSource> install(MangayomiSource source) async {
    await _load();
    final codeUrl =
        source.codeLanguage == MangayomiCodeLanguage.javascript &&
            source.codeUrl.path.endsWith('/javascript/')
        ? source.codeUrl.resolve(
            '${switch (source.contentType) {
              MangayomiContentType.video => 'anime',
              MangayomiContentType.manga => 'manga',
              MangayomiContentType.novel => 'novel',
            }}/src/${source.language}/${Uri.encodeComponent(source.name)}.js',
          )
        : source.codeUrl;
    // shortcut: supports the standard Mangayomi JS tree only; add another layout when a repo uses one.
    final code = await _download(codeUrl, 2 * 1024 * 1024);
    if (code.isEmpty) throw const FormatException('Empty source code');
    final digest = sha256.convert(code).toString();
    final file = File(path.join(directory.path, '$digest.source'));
    if (!await file.exists()) {
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(code, flush: true);
      await temp.rename(file.path);
    }

    final previous = _installed![source.key];
    final item = InstalledMangayomiSource(source, file);
    _installed![source.key] = item;
    try {
      await _save();
    } catch (_) {
      if (previous == null) {
        _installed!.remove(source.key);
      } else {
        _installed![source.key] = previous;
      }
      rethrow;
    }
    if (previous != null && previous.codeFile.path != file.path) {
      await _deleteUnused(previous.codeFile);
    }
    return item;
  }

  Future<void> uninstall(String key) async {
    await _load();
    final previous = _installed!.remove(key);
    if (previous == null) return;
    try {
      await _save();
    } catch (_) {
      _installed![key] = previous;
      rethrow;
    }
    await _deleteUnused(previous.codeFile);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<void> _load() async {
    if (_installed != null) return;
    await directory.create(recursive: true);
    final file = File(path.join(directory.path, 'installed.json'));
    final entries = await file.exists()
        ? jsonDecode(await file.readAsString())
        : <Object>[];
    if (entries is! List) {
      throw const FormatException('Invalid installed source index');
    }
    final installed = <String, InstalledMangayomiSource>{};
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid installed source');
      }
      final repository = Uri.parse(entry['repository'] as String);
      final source = MangayomiSource.fromManifest(
        entry['source'] as Map<String, dynamic>,
        repository,
      );
      final fileName = entry['codeFile'] as String;
      if (!RegExp(r'^[a-f0-9]{64}\.source$').hasMatch(fileName)) {
        throw const FormatException('Invalid source code filename');
      }
      final codeFile = File(path.join(directory.path, fileName));
      if (await codeFile.exists()) {
        installed[source.key] = InstalledMangayomiSource(source, codeFile);
      }
    }
    _installed = installed;
  }

  Future<void> _save() async {
    final entries = [
      for (final item in _installed!.values)
        {
          'repository': item.source.repository.toString(),
          'source': item.source.toManifest(),
          'codeFile': path.basename(item.codeFile.path),
        },
    ];
    final file = File(path.join(directory.path, 'installed.json'));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(entries), flush: true);
    await temp.rename(file.path);
  }

  Future<void> _deleteUnused(File file) async {
    if (_installed!.values.any((item) => item.codeFile.path == file.path)) {
      return;
    }
    if (await file.exists()) await file.delete();
  }

  Future<List<int>> _download(Uri url, int limit) async {
    var current = url;
    http.StreamedResponse? response;
    for (var redirects = 0; redirects <= 3; redirects++) {
      final request = http.Request('GET', current)..followRedirects = false;
      response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
      final location = response.headers['location'];
      if (location == null || redirects == 3) {
        throw HttpException('Too many redirects', uri: current);
      }
      current = current.resolve(location);
      if (current.scheme != 'https' || current.userInfo.isNotEmpty) {
        throw HttpException(
          'Download redirected to an unsafe URL',
          uri: current,
        );
      }
    }
    if (response == null) throw StateError('No download response');
    if (response.statusCode != 200) {
      throw HttpException(
        'Download failed (${response.statusCode})',
        uri: current,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > limit) {
        throw const FormatException('Download is too large');
      }
    }
    return bytes;
  }
}
