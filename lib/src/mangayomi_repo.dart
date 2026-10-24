import 'dart:convert';

import 'mangayomi_source.dart';

class MangayomiRepository {
  MangayomiRepository(this.url);

  final Uri url;

  List<MangayomiSource> parseIndex(String body) {
    if (body.length > 5 * 1024 * 1024) {
      throw const FormatException('Repository index is too large');
    }
    final decoded = jsonDecode(body);
    if (decoded is! List || decoded.length > 10000) {
      throw const FormatException('Invalid repository index');
    }
    final sources = [
      for (final (index, item) in decoded.indexed)
        if (item is Map<String, dynamic>)
          MangayomiSource.fromManifest(item, url)
        else
          throw FormatException('Invalid source at index $index'),
    ];
    if (sources.map((source) => source.key).toSet().length != sources.length) {
      throw const FormatException('Duplicate source in repository index');
    }
    return sources;
  }
}
