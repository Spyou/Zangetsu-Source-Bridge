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
    final unique = <String, MangayomiSource>{};
    for (final source in sources) {
      final existing = unique[source.key];
      if (existing == null) {
        unique[source.key] = source;
      } else if (jsonEncode(existing.toManifest()) !=
          jsonEncode(source.toManifest())) {
        throw const FormatException('Conflicting source in repository index');
      }
    }
    return unique.values.toList();
  }
}
