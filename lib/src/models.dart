enum MStatus {
  ongoing,
  completed,
  canceled,
  unknown,
  onHiatus,
  publishingFinished,
}

class MSource {
  int? id;
  String? name;
  String? baseUrl;
  String? lang;
  bool? isFullData;
  bool? hasCloudflare;
  String? dateFormat;
  String? dateFormatLocale;
  String? apiUrl;
  String? additionalParams;
  String? notes;

  MSource({
    this.id,
    this.name,
    this.baseUrl,
    this.lang,
    this.isFullData,
    this.hasCloudflare,
    this.dateFormat,
    this.dateFormatLocale,
    this.apiUrl,
    this.additionalParams,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'apiUrl': apiUrl,
    'baseUrl': baseUrl,
    'dateFormat': dateFormat,
    'dateFormatLocale': dateFormatLocale,
    'hasCloudflare': hasCloudflare,
    'id': id,
    'isFullData': isFullData,
    'lang': lang,
    'name': name,
    'additionalParams': additionalParams,
    'notes': notes,
  };
}

class MManga {
  String? name;
  String? link;
  String? imageUrl;
  String? description;
  String? author;
  String? artist;
  MStatus? status;
  List<String>? genre;
  List<MChapter>? chapters;

  MManga({
    this.author,
    this.artist,
    this.genre,
    this.imageUrl,
    this.link,
    this.name,
    this.status = MStatus.unknown,
    this.description,
    this.chapters,
  });
}

class MChapter {
  String? name;
  String? url;
  String? dateUpload;
  String? scanlator;
  bool? isFiller;
  String? thumbnailUrl;
  String? description;
  String? downloadSize;
  String? duration;

  MChapter({
    this.name,
    this.url,
    this.dateUpload,
    this.scanlator,
    this.isFiller = false,
    this.thumbnailUrl,
    this.description,
    this.downloadSize,
    this.duration,
  });
}

class MPages {
  List<MManga> list;
  bool hasNextPage;

  MPages({required this.list, this.hasNextPage = false});
}

class Track {
  String? file;
  String? label;

  Track({this.file, this.label});
}

class MVideo {
  String url;
  String quality;
  String originalUrl;
  Map<String, String>? headers;
  List<Track>? subtitles;
  List<Track>? audios;

  MVideo(
    this.url,
    this.quality,
    this.originalUrl, {
    this.headers,
    this.subtitles,
    this.audios,
  });
}

class MPage {
  MPage(this.url, {this.headers});

  final String url;
  final Map<String, String>? headers;
}

class MProviderBase {
  dynamic source;

  bool get supportsLatest => false;
  String get baseUrl => throw UnimplementedError('baseUrl not implemented');
  Map<String, String> get headers => {};
}

class FilterList {
  List<dynamic> filters;
  FilterList(this.filters);
}

class SelectFilter {
  String? type;
  String name;
  int state;
  List<dynamic> values;
  String? typeName;

  SelectFilter(this.type, this.name, this.state, this.values, [this.typeName]);
}

class SelectFilterOption {
  String name;
  String value;
  String? typeName;

  SelectFilterOption(this.name, this.value, [this.typeName]);
}

class SeparatorFilter {
  String? type;
  String? typeName;

  SeparatorFilter([this.typeName, this.type = '']);
}

class HeaderFilter {
  String? type;
  String name;
  String? typeName;

  HeaderFilter(this.name, [this.typeName, this.type = '']);
}

class TextFilter {
  String? type;
  String name;
  String state;
  String? typeName;

  TextFilter(this.type, this.name, [this.typeName, this.state = '']);
}

class SortFilter {
  String? type;
  String name;
  SortState state;
  List<dynamic> values;
  String? typeName;

  SortFilter(this.type, this.name, this.state, this.values, [this.typeName]);
}

class SortState {
  int index;
  bool ascending;
  String? typeName;

  SortState(this.index, this.ascending, [this.typeName]);
}

class TriStateFilter {
  String? type;
  String name;
  String value;
  int state;
  String? typeName;

  TriStateFilter(
    this.name,
    this.value, [
    this.type,
    this.typeName,
    this.state = 0,
  ]);
}

class GroupFilter {
  String? type;
  String name;
  List<dynamic> state;
  String? typeName;

  GroupFilter(this.type, this.name, this.state, [this.typeName]);
}

class CheckBoxFilter {
  String? type;
  String name;
  String value;
  bool state;
  String? typeName;

  CheckBoxFilter(
    this.name,
    this.value, [
    this.type,
    this.state = false,
    this.typeName,
  ]);
}

class ListPreference {
  String? key;
  String? title;
  String? summary;
  int? valueIndex;
  List<String>? entries;
  List<String>? entryValues;

  ListPreference({
    this.key,
    this.title,
    this.summary,
    this.valueIndex,
    this.entries,
    this.entryValues,
  });
}

class EditTextPreference {
  String? key;
  String? title;
  String? summary;
  String? value;

  EditTextPreference({this.key, this.title, this.summary, this.value});
}

class SwitchPreferenceCompat {
  String? key;
  String? title;
  String? summary;
  bool? value;

  SwitchPreferenceCompat({this.key, this.title, this.summary, this.value});
}

class CheckBoxPreference {
  String? key;
  String? title;
  String? summary;
  bool? value;

  CheckBoxPreference({this.key, this.title, this.summary, this.value});
}
