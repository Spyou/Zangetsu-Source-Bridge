import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';

enum MangayomiContentType { manga, video, novel }

enum MangayomiCodeLanguage { dart, javascript }

class MangayomiSource {
  MangayomiSource({
    required this.repository,
    required this.key,
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.codeUrl,
    required this.version,
    required this.contentType,
    required this.codeLanguage,
    required this.language,
    this.iconUrl,
    this.apiUrl,
    this.isNsfw = false,
    this.hasCloudflare = false,
    this.isFullData = false,
    this.dateFormat,
    this.dateFormatLocale,
    this.additionalParams,
    this.notes,
    this.minimumAppVersion,
  });

  final Uri repository;
  final String key;
  final int id;
  final String name;
  final Uri baseUrl;
  final Uri codeUrl;
  final String version;
  final MangayomiContentType contentType;
  final MangayomiCodeLanguage codeLanguage;
  final String language;
  final Uri? iconUrl;
  final Uri? apiUrl;
  final bool isNsfw;
  final bool hasCloudflare;
  final bool isFullData;
  final String? dateFormat;
  final String? dateFormatLocale;
  final String? additionalParams;
  final String? notes;
  final String? minimumAppVersion;

  factory MangayomiSource.fromManifest(
    Map<String, dynamic> data,
    Uri repository,
  ) {
    String requiredText(String field) {
      final value = data[field];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Missing $field');
      }
      return value.trim();
    }

    Uri webUrl(String value, String field, {bool secure = false}) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          (uri.scheme != 'https' && (secure || uri.scheme != 'http')) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw FormatException('Invalid $field URL');
      }
      return uri;
    }

    if (repository.scheme != 'https' ||
        repository.host.isEmpty ||
        repository.userInfo.isNotEmpty) {
      throw const FormatException('Invalid repository URL');
    }
    final id = data['id'];
    final type = data['itemType'];
    final language = data['sourceCodeLanguage'];
    if (id is! int ||
        id == 0 ||
        type is! int ||
        type < 0 ||
        type > 2 ||
        language is! int ||
        language < 0 ||
        language > 1) {
      throw const FormatException('Invalid source ID, type, or code language');
    }
    final repositoryId = repository.resolve('.').toString();
    final digest = sha256.convert(utf8.encode(repositoryId)).toString();
    final icon = data['iconUrl'];
    final api = data['apiUrl'];
    return MangayomiSource(
      repository: repository,
      key: 'mg:$digest:$type:$language:$id',
      id: id,
      name: requiredText('name'),
      baseUrl: webUrl(requiredText('baseUrl'), 'base'),
      codeUrl: webUrl(
        requiredText('sourceCodeUrl'),
        'source code',
        secure: true,
      ),
      version: requiredText('version'),
      contentType: MangayomiContentType.values[type],
      codeLanguage: MangayomiCodeLanguage.values[language],
      language: requiredText('lang'),
      iconUrl: icon is String && icon.isNotEmpty ? webUrl(icon, 'icon') : null,
      apiUrl: api is String && api.isNotEmpty ? webUrl(api, 'API') : null,
      isNsfw: data['isNsfw'] == true,
      hasCloudflare: data['hasCloudflare'] == true,
      isFullData: data['isFullData'] == true,
      dateFormat: data['dateFormat'] as String?,
      dateFormatLocale: data['dateFormatLocale'] as String?,
      additionalParams: data['additionalParams'] as String?,
      notes: data['notes'] as String?,
      minimumAppVersion: data['appMinVerReq'] as String?,
    );
  }

  MSource toRuntimeSource() => MSource(
    id: id,
    name: name,
    baseUrl: baseUrl.toString(),
    apiUrl: apiUrl?.toString(),
    lang: language,
    isFullData: isFullData,
    hasCloudflare: hasCloudflare,
    dateFormat: dateFormat,
    dateFormatLocale: dateFormatLocale,
    additionalParams: additionalParams,
    notes: notes,
  );

  Map<String, Object?> toManifest() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl.toString(),
    'sourceCodeUrl': codeUrl.toString(),
    'version': version,
    'itemType': contentType.index,
    'sourceCodeLanguage': codeLanguage.index,
    'lang': language,
    'iconUrl': iconUrl?.toString() ?? '',
    'apiUrl': apiUrl?.toString() ?? '',
    'isNsfw': isNsfw,
    'hasCloudflare': hasCloudflare,
    'isFullData': isFullData,
    'dateFormat': dateFormat,
    'dateFormatLocale': dateFormatLocale,
    'additionalParams': additionalParams,
    'notes': notes,
    'appMinVerReq': minimumAppVersion,
  };
}
