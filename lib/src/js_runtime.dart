import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;

import 'html.dart';
import 'cloudflare_http.dart';
import 'models.dart';

class JsSourceRuntime {
  JsSourceRuntime(
    this.source,
    this.sourceCode, {
    Map<String, dynamic>? preferences,
  }) : preferences = Map.of(preferences ?? const {});

  final MSource source;
  final String sourceCode;
  final Map<String, dynamic> preferences;

  JavascriptRuntime? _runtime;
  _JsHttp? _http;
  bool _initialized = false;

  JavascriptRuntime get runtime {
    final rt = _runtime;
    if (rt == null) throw StateError('JS runtime not initialized');
    return rt;
  }

  void init() {
    if (_initialized) return;
    final rt = getJavascriptRuntime(xhr: false);
    _runtime = rt;
    _http = _JsHttp(rt, source)..init();
    _JsDom(rt).init();
    _JsPrefs(rt, preferences).init();
    _registerCommon(rt);
    rt.evaluate(_providerSource(jsonEncode(source.toJson())));
    _eval(
      rt,
      '$sourceCode\nvar extention = new DefaultExtension();',
      'loading the source',
    );
    _seedPreferenceDefaults(rt);
    _initialized = true;
  }

  void _seedPreferenceDefaults(JavascriptRuntime rt) {
    try {
      final result = rt.evaluate(
        'JSON.stringify(extention.getSourcePreferences())',
      );
      if (result.isError) return;
      final list = jsonDecode(result.stringResult);
      if (list is! List) return;
      for (final item in list) {
        if (item is! Map) continue;
        final key = item['key']?.toString();
        if (key == null) continue;
        final edit = item['editTextPreference'];
        final listPref = item['listPreference'];
        final multiPref = item['multiSelectListPreference'];
        final switchPref = item['switchPreferenceCompat'];
        final checkPref = item['checkBoxPreference'];
        if (edit is Map && edit['value'] != null) {
          preferences.putIfAbsent(key, () => edit['value']);
        } else if (listPref is Map) {
          final values = listPref['entryValues'];
          final index = listPref['valueIndex'] ?? 0;
          if (values is List &&
              index is int &&
              index >= 0 &&
              index < values.length) {
            preferences.putIfAbsent(key, () => values[index]);
          }
        } else if (multiPref is Map) {
          preferences.putIfAbsent(key, () => multiPref['values'] ?? const []);
        } else if (switchPref is Map) {
          preferences.putIfAbsent(key, () => switchPref['value'] ?? false);
        } else if (checkPref is Map) {
          preferences.putIfAbsent(key, () => checkPref['value'] ?? false);
        }
      }
    } catch (_) {}
  }

  Future<T> call<T>(String call) async {
    init();
    final evaluated = await runtime.evaluateAsync(
      'jsonStringify(() => extention.$call)',
    );
    if (evaluated.isError) {
      throw Exception(
        'Extension "${source.name ?? 'unknown'}" failed while $call: ${evaluated.stringResult}',
      );
    }
    final promised = await runtime.handlePromise(evaluated);
    if (promised.isError) {
      throw Exception(
        'Extension "${source.name ?? 'unknown'}" failed while $call: ${promised.stringResult}',
      );
    }
    var decoded = jsonDecode(promised.stringResult);
    if (decoded is String) {
      final trimmed = decoded.trim();
      if (trimmed.startsWith('[') ||
          trimmed.startsWith('{') ||
          trimmed.startsWith('"')) {
        try {
          decoded = jsonDecode(trimmed);
        } catch (_) {}
      }
    }
    if (decoded is Map && decoded['__bridge_error'] is String) {
      throw StateError(
        'Extension "${source.name ?? 'unknown'}" failed while $call: ${decoded['__bridge_error']}',
      );
    }
    return decoded as T;
  }

  Future<MPages> getPopular(int page) async {
    final json = await call<Map<String, dynamic>>('getPopular($page)');
    return _pages(json);
  }

  Future<MPages> getLatestUpdates(int page) async {
    final json = await call<Map<String, dynamic>>('getLatestUpdates($page)');
    return _pages(json);
  }

  Future<MPages> search(
    String query,
    int page, [
    List<dynamic> filters = const [],
  ]) async {
    final json = await call<Map<String, dynamic>>(
      'search(${jsonEncode(query)},$page,${jsonEncode(filters)})',
    );
    return _pages(json);
  }

  Future<MManga> getDetail(String url) async {
    final json = await call<Map<String, dynamic>>(
      'getDetail(${jsonEncode(url)})',
    );
    return _manga(json);
  }

  Future<List<MVideo>> getVideoList(String url) async {
    final list = await call<List>('getVideoList(${jsonEncode(url)})');
    final result = <MVideo>[];
    for (final element in list) {
      if (element is Map &&
          element['url'] != null &&
          element['originalUrl'] != null) {
        result.add(
          MVideo(
            element['url'].toString().trim(),
            element['quality']?.toString().trim() ?? '',
            element['originalUrl'].toString().trim(),
            headers: _stringMap(element['headers']),
            subtitles: _tracks(element['subtitles']),
            audios: _tracks(element['audios']),
          ),
        );
      }
    }
    return result;
  }

  Future<List<MPage>> getPageList(String url) async {
    final list = await call<List>('getPageList(${jsonEncode(url)})');
    return list
        .map(
          (e) => e is Map
              ? MPage(e['url'].toString(), headers: _stringMap(e['headers']))
              : MPage(e.toString()),
        )
        .toList();
  }

  Future<String> getHtmlContent(String name, String url) async {
    return call<String>(
      'getHtmlContent(${jsonEncode(name)}, ${jsonEncode(url)})',
    );
  }

  Future<String> cleanHtmlContent(String html) async {
    return call<String>('cleanHtmlContent(${jsonEncode(html)})');
  }

  void dispose() {
    _http?.close();
    _http = null;
    _runtime?.dispose();
    _runtime = null;
    _initialized = false;
  }

  MPages _pages(Map<String, dynamic> json) {
    final list = json['list'];
    return MPages(
      list: list is List
          ? list.whereType<Map>().map((e) => _manga(e.cast())).toList()
          : [],
      hasNextPage: json['hasNextPage'] == true,
    );
  }

  MManga _manga(Map<String, dynamic> json) {
    final chapters = json['chapters'] ?? json['episodes'];
    return MManga(
      name: json['name'],
      link: json['link'],
      imageUrl: json['imageUrl'],
      description: json['description'],
      author: json['author'],
      artist: json['artist'],
      status: switch (json['status']) {
        0 => MStatus.ongoing,
        1 => MStatus.completed,
        2 => MStatus.onHiatus,
        3 => MStatus.canceled,
        4 => MStatus.publishingFinished,
        _ => MStatus.unknown,
      },
      genre: (json['genre'] as List?)?.map((e) => e.toString()).toList(),
      chapters: chapters is List
          ? chapters
                .whereType<Map>()
                .map(
                  (e) => MChapter(
                    name: e['name'],
                    url: e['url'],
                    dateUpload: e['dateUpload'],
                    scanlator: e['scanlator'],
                    isFiller: e['isFiller'] == true,
                    thumbnailUrl: e['thumbnailUrl'],
                    description: e['description'],
                  ),
                )
                .toList()
          : [],
    );
  }

  static Map<String, String>? _stringMap(Object? value) {
    if (value is! Map) return null;
    return value.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  static List<Track>? _tracks(Object? value) {
    if (value is! List) return null;
    return value
        .whereType<Map>()
        .map((e) => Track(file: e['file'], label: e['label']))
        .toList();
  }
}

String _providerSource(String sourceJson) =>
    '''
class MProvider {
  get source() { return $sourceJson; }
  get supportsLatest() { throw new Error("supportsLatest not implemented"); }
  getHeaders(url) { throw new Error("getHeaders not implemented"); }
  async getPopular(page) { throw new Error("getPopular not implemented"); }
  async getLatestUpdates(page) { throw new Error("getLatestUpdates not implemented"); }
  async search(query, page, filters) { throw new Error("search not implemented"); }
  async getDetail(url) { throw new Error("getDetail not implemented"); }
  async getPageList() { throw new Error("getPageList not implemented"); }
  async getVideoList(url) { throw new Error("getVideoList not implemented"); }
  async getHtmlContent(name, url) { throw new Error("getHtmlContent not implemented"); }
  async cleanHtmlContent(html) { throw new Error("cleanHtmlContent not implemented"); }
  getFilterList() { throw new Error("getFilterList not implemented"); }
  getSourcePreferences() { throw new Error("getSourcePreferences not implemented"); }
}
async function jsonStringify(fn) {
  try { return JSON.stringify(await fn()); }
  catch (error) { return JSON.stringify({__bridge_error: String(error)}); }
}
''';

void _registerCommon(JavascriptRuntime rt) {
  rt.onMessage('log', (dynamic args) {
    if (kDebugMode) debugPrint('Mangayomi JS: ${args[0]}');
    return null;
  });
  rt.evaluate('''
String.prototype.substringAfter = function(pattern) {
  const i = this.indexOf(pattern);
  return i === -1 ? this.substring(0) : this.substring(i + pattern.length);
};
String.prototype.substringAfterLast = function(pattern) { return this.split(pattern).pop(); };
String.prototype.substringBefore = function(pattern) {
  const i = this.indexOf(pattern);
  return i === -1 ? this.substring(0) : this.substring(0, i);
};
String.prototype.substringBeforeLast = function(pattern) {
  const i = this.lastIndexOf(pattern);
  return i === -1 ? this.substring(0) : this.substring(0, i);
};
''');
}

void _eval(JavascriptRuntime rt, String code, String what) {
  final result = rt.evaluate(code);
  if (result.isError) {
    throw Exception('Extension failed while $what: ${result.stringResult}');
  }
}

class _JsHttp {
  _JsHttp(this.rt, MSource source)
    : _client = MangayomiHttpClient(protected: source.hasCloudflare ?? false);
  final JavascriptRuntime rt;
  final http.Client _client;

  void close() => _client.close();

  void init() {
    rt.onMessage('http_head', (args) => _request('HEAD', args));
    rt.onMessage('http_get', (args) => _request('GET', args));
    rt.onMessage('http_post', (args) => _request('POST', args));
    rt.onMessage('http_put', (args) => _request('PUT', args));
    rt.onMessage('http_delete', (args) => _request('DELETE', args));
    rt.onMessage('http_patch', (args) => _request('PATCH', args));
    rt.evaluate('''
class Client {
  constructor(reqcopyWith) { this.reqcopyWith = reqcopyWith; }
  async _send(method, url, headers, body) {
    const raw = await sendMessage("http_" + method.toLowerCase(), JSON.stringify([null, this.reqcopyWith, url, headers, body]));
    return JSON.parse(raw);
  }
  head(url, headers) { return this._send("HEAD", url, headers); }
  get(url, headers) { return this._send("GET", url, headers); }
  post(url, headers, body) { return this._send("POST", url, headers, body); }
  put(url, headers, body) { return this._send("PUT", url, headers, body); }
  delete(url, headers, body) { return this._send("DELETE", url, headers, body); }
  patch(url, headers, body) { return this._send("PATCH", url, headers, body); }
}
''');
  }

  Future<String> _request(String method, dynamic args) async {
    final url = args[2] as String;
    final headers = <String, String>{
      if (args[3] is Map)
        ...(args[3] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
    };
    headers.putIfAbsent(
      HttpHeaders.userAgentHeader,
      () =>
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    );
    final body = args.length >= 5 ? args[4] : null;
    late http.Response response;
    if (method == 'POST' ||
        method == 'PUT' ||
        method == 'PATCH' ||
        method == 'DELETE') {
      response = await _client.post(
        Uri.parse(url),
        headers: headers,
        body: body is String ? body : (body is List ? body : jsonEncode(body)),
      );
    } else if (method == 'HEAD') {
      response = await _client.head(Uri.parse(url), headers: headers);
    } else {
      response = await _client.get(Uri.parse(url), headers: headers);
    }
    return jsonEncode({
      'body': response.body,
      'headers': response.headers,
      'isRedirect': response.isRedirect,
      'persistentConnection': response.persistentConnection,
      'reasonPhrase': response.reasonPhrase,
      'statusCode': response.statusCode,
      'request': {'url': url, 'method': method},
    });
  }
}

class _JsDom {
  _JsDom(this.rt);
  final JavascriptRuntime rt;
  final Map<int, dynamic> _elements = {};
  int _key = 0;

  int _put(Object? element) {
    _key++;
    _elements[_key] = element;
    return _key;
  }

  void init() {
    rt.onMessage('get_doc_element', (args) {
      final doc = MDocument.parse(args[0] as String);
      return _put(switch (args[1]) {
        'body' => doc.body,
        'documentElement' => doc.documentElement,
        'head' => doc.head,
        _ => doc.parent,
      });
    });
    rt.onMessage('get_doc_string', (args) {
      final doc = MDocument.parse(args[0] as String);
      return args[1] == 'text' ? doc.text : doc.outerHtml;
    });
    rt.onMessage('get_element_string', (args) {
      final element = _elements[args[1]] as MElement?;
      return switch (args[0]) {
            'text' => element?.text,
            'innerHtml' => element?.innerHtml,
            'outerHtml' => element?.outerHtml,
            'className' => element?.className,
            'localName' => element?.localName,
            'namespaceUri' => element?.namespaceUri,
            'getSrc' => element?.getSrc,
            'getImg' => element?.getImg,
            'getHref' => element?.getHref,
            _ => element?.getDataSrc,
          } ??
          '';
    });
    rt.onMessage(
      'doc_select_first',
      (args) => _put(
        MDocument.parse(args[0] as String).selectFirst(args[1] as String),
      ),
    );
    rt.onMessage(
      'ele_selectFirst',
      (args) => _put(
        (_elements[args[1]] as MElement?)?.selectFirst(args[0] as String),
      ),
    );
    rt.onMessage('ele_element_sibling', (args) {
      final element = _elements[args[1]] as MElement?;
      return _put(
        args[0] == 'nextElementSibling'
            ? element?.nextElementSibling
            : element?.previousElementSibling,
      );
    });
    rt.onMessage(
      'ele_attr',
      (args) =>
          (_elements[args[1]] as MElement?)?.attr(args[0] as String) ?? '',
    );
    rt.onMessage(
      'doc_attr',
      (args) =>
          MDocument.parse(args[0] as String).attr(args[1] as String) ?? '',
    );
    rt.onMessage(
      'ele_has_attr',
      (args) =>
          (_elements[args[1]] as MElement?)?.hasAttr(args[0] as String) ??
          false,
    );
    rt.onMessage(
      'doc_has_attr',
      (args) => MDocument.parse(args[0] as String).hasAttr(args[1] as String),
    );
    rt.onMessage(
      'doc_xpath_first',
      (args) =>
          MDocument.parse(args[0] as String).xpathFirst(args[1] as String) ??
          '',
    );
    rt.onMessage(
      'ele_xpathFirst',
      (args) =>
          (_elements[args[1]] as MElement?)?.xpathFirst(args[0] as String) ??
          '',
    );
    rt.onMessage(
      'doc_xpath',
      (args) => jsonEncode(
        MDocument.parse(args[0] as String).xpath(args[1] as String),
      ),
    );
    rt.onMessage(
      'ele_xpath',
      (args) => jsonEncode(
        (_elements[args[1]] as MElement?)?.xpath(args[0] as String) ?? [],
      ),
    );
    rt.onMessage('doc_get_elements_by', (args) {
      final doc = MDocument.parse(args[0] as String);
      final elements = switch (args[1]) {
        'children' => doc.children,
        'getElementsByTagName' => doc.getElementsByTagName(args[2] as String),
        _ => doc.getElementsByClassName(args[2] as String),
      };
      return jsonEncode((elements ?? []).map(_put).toList());
    });
    rt.onMessage('ele_get_elements_by', (args) {
      final element = _elements[args[2]] as MElement?;
      final elements = switch (args[0]) {
        'children' => element?.children,
        'getElementsByTagName' => element?.getElementsByTagName(
          args[1] as String,
        ),
        _ => element?.getElementsByClassName(args[1] as String),
      };
      return jsonEncode((elements ?? []).map(_put).toList());
    });
    rt.onMessage(
      'doc_get_element_by_id',
      (args) => _put(
        MDocument.parse(args[0] as String).getElementById(args[1] as String),
      ),
    );
    rt.onMessage('doc_select', (args) {
      final elements =
          MDocument.parse(args[0] as String).select(args[1] as String) ?? [];
      return jsonEncode(elements.map(_put).toList());
    });
    rt.onMessage('ele_select', (args) {
      final elements =
          (_elements[args[1]] as MElement?)?.select(args[0] as String) ?? [];
      return jsonEncode(elements.map(_put).toList());
    });

    rt.evaluate('''
class Document {
  constructor(html) { this.html = html; }
  getElement(type) { return new Element(sendMessage("get_doc_element", JSON.stringify([this.html, type]))); }
  get body() { return this.getElement('body'); }
  get documentElement() { return this.getElement('documentElement'); }
  get head() { return this.getElement('head'); }
  get parent() { return this.getElement('parent'); }
  getString(type) { return sendMessage("get_doc_string", JSON.stringify([this.html, type])); }
  get text() { return this.getString('text'); }
  get outerHtml() { return this.getString('outerHtml'); }
  selectFirst(selector) { return new Element(sendMessage("doc_select_first", JSON.stringify([this.html, selector]))); }
  select(selector) {
    return JSON.parse(sendMessage("doc_select", JSON.stringify([this.html, selector]))).map((key) => new Element(key));
  }
  xpathFirst(xpath) { return sendMessage("doc_xpath_first", JSON.stringify([this.html, xpath])); }
  xpath(xpath) { return JSON.parse(sendMessage("doc_xpath", JSON.stringify([this.html, xpath]))); }
  getElementsListBy(type, name) {
    return JSON.parse(sendMessage("doc_get_elements_by", JSON.stringify([this.html, type, name || '']))).map((key) => new Element(key));
  }
  get children() { return this.getElementsListBy('children'); }
  getElementsByTagName(name) { return this.getElementsListBy('getElementsByTagName', name); }
  getElementsByClassName(name) { return this.getElementsListBy('getElementsByClassName', name); }
  getElementById(id) { return new Element(sendMessage("doc_get_element_by_id", JSON.stringify([this.html, id]))); }
  attr(attr) { return sendMessage("doc_attr", JSON.stringify([this.html, attr])); }
  hasAttr(attr) { return sendMessage("doc_has_attr", JSON.stringify([this.html, attr])); }
}
class Element {
  constructor(key) { this.key = key; }
  getString(type) { return sendMessage("get_element_string", JSON.stringify([type, this.key])); }
  get text() { return this.getString("text"); }
  get outerHtml() { return this.getString("outerHtml"); }
  get innerHtml() { return this.getString("innerHtml"); }
  get className() { return this.getString("className"); }
  get localName() { return this.getString("localName"); }
  get namespaceUri() { return this.getString("namespaceUri"); }
  get getSrc() { return this.getString("getSrc"); }
  get getImg() { return this.getString("getImg"); }
  get getHref() { return this.getString("getHref"); }
  get getDataSrc() { return this.getString("getDataSrc"); }
  getElementSibling(type) { return new Element(sendMessage("ele_element_sibling", JSON.stringify([type, this.key]))); }
  get previousElementSibling() { return this.getElementSibling("previousElementSibling"); }
  get nextElementSibling() { return this.getElementSibling("nextElementSibling"); }
  getElementsListBy(type, name) {
    return JSON.parse(sendMessage("ele_get_elements_by", JSON.stringify([type, name || '', this.key]))).map((key) => new Element(key));
  }
  get children() { return this.getElementsListBy('children'); }
  getElementsByTagName(name) { return this.getElementsListBy('getElementsByTagName', name); }
  getElementsByClassName(name) { return this.getElementsListBy('getElementsByClassName', name); }
  xpath(xpath) { return JSON.parse(sendMessage("ele_xpath", JSON.stringify([xpath, this.key]))); }
  xpathFirst(xpath) { return sendMessage("ele_xpathFirst", JSON.stringify([xpath, this.key])); }
  attr(attr) { return sendMessage("ele_attr", JSON.stringify([attr, this.key])); }
  hasAttr(attr) { return sendMessage("ele_has_attr", JSON.stringify([attr, this.key])); }
  selectFirst(selector) { return new Element(sendMessage("ele_selectFirst", JSON.stringify([selector, this.key]))); }
  select(selector) {
    return JSON.parse(sendMessage("ele_select", JSON.stringify([selector, this.key]))).map((key) => new Element(key));
  }
}
''');
  }
}

class _JsPrefs {
  _JsPrefs(this.rt, this.preferences);
  final JavascriptRuntime rt;
  final Map<String, dynamic> preferences;

  void init() {
    rt.onMessage('get', (args) {
      final key = args[0].toString();
      if (!preferences.containsKey(key)) return jsonEncode({'found': false});
      return jsonEncode({'found': true, 'value': preferences[key]});
    });
    rt.onMessage('getString', (args) {
      final key = args[0].toString();
      final value = preferences[key];
      return value?.toString() ?? args[1].toString();
    });
    rt.onMessage('setString', (args) {
      preferences[args[0].toString()] = args[1];
      return true;
    });
    rt.evaluate('''
class SharedPreferences {
  get(key, defaultValue) {
    const result = JSON.parse(sendMessage("get", JSON.stringify([key])));
    return result.found ? result.value : defaultValue;
  }
  getString(key, defaultValue) {
    return sendMessage("getString", JSON.stringify([key, defaultValue === undefined ? "" : defaultValue]));
  }
  setString(key, value) {
    return sendMessage("setString", JSON.stringify([key, value === undefined ? "" : value]));
  }
}
''');
  }
}
