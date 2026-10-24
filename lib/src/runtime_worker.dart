import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'dart_runtime.dart';
import 'js_runtime.dart';
import 'mangayomi_config.dart';
import 'mangayomi_source.dart';
import 'models.dart';

class MangayomiRuntimeWorker {
  MangayomiRuntimeWorker(
    this.source,
    this.sourceCode,
    this.language, {
    this.preferences = const {},
    this.callTimeout = const Duration(seconds: 30),
    this.rootToken,
  });

  final MSource source;
  final String sourceCode;
  final MangayomiCodeLanguage language;
  final Map<String, dynamic> preferences;
  final Duration callTimeout;
  final RootIsolateToken? rootToken;

  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  SendPort? _commands;
  Completer<void>? _ready;
  Future<void>? _starting;
  final Map<int, Completer<Object?>> _pending = {};
  var _nextId = 0;
  var _disposed = false;

  Future<void> _start() => _starting ??= _spawn();

  Future<void> _spawn() async {
    final token = rootToken ?? RootIsolateToken.instance;
    if ((Platform.isAndroid || Platform.isIOS) && token == null) {
      throw StateError('A root isolate token is required on mobile');
    }
    final ready = _ready = Completer<void>();
    _responses = ReceivePort()..listen(_onResponse);
    _errors = ReceivePort()
      ..listen(
        (message) => _abort(StateError('Source worker failed: $message')),
      );
    _exits = ReceivePort()
      ..listen((_) => _abort(StateError('Source worker exited')));
    try {
      _isolate = await Isolate.spawn(
        _runWorker,
        _WorkerInit(
          _responses!.sendPort,
          token,
          source,
          sourceCode,
          language,
          preferences,
        ),
        onError: _errors!.sendPort,
        onExit: _exits!.sendPort,
        errorsAreFatal: true,
      );
      await ready.future.timeout(const Duration(seconds: 10));
    } catch (error) {
      _abort(error);
      rethrow;
    }
  }

  void _onResponse(dynamic message) {
    if (message is SendPort) {
      _commands = message;
      if (_ready?.isCompleted == false) _ready!.complete();
      return;
    }
    if (message is! List || message.length != 3) return;
    final pending = _pending.remove(message[0]);
    if (pending == null || pending.isCompleted) return;
    if (message[1] == true) {
      pending.complete(message[2]);
    } else {
      pending.completeError(StateError(message[2].toString()));
    }
  }

  Future<T> call<T>(
    String operation, [
    List<Object?> arguments = const [],
  ]) async {
    if (_disposed) throw StateError('Source worker is disposed');
    await _start();
    final id = ++_nextId;
    final pending = Completer<Object?>();
    _pending[id] = pending;
    _commands!.send([id, operation, arguments]);
    try {
      return (await pending.future.timeout(callTimeout)) as T;
    } on TimeoutException {
      cancel();
      rethrow;
    }
  }

  Future<MPages> getPopular(int page) => call('getPopular', [page]);
  Future<MPages> getLatestUpdates(int page) => call('getLatestUpdates', [page]);
  Future<MPages> search(
    String query,
    int page, [
    List<dynamic> filters = const [],
  ]) => call('search', [query, page, filters]);
  Future<List<dynamic>> getFilterList() => call('getFilterList');
  Future<List<dynamic>> getSourcePreferences() => call('getSourcePreferences');
  Future<MManga> getDetail(String url) => call('getDetail', [url]);
  Future<List<MVideo>> getVideoList(String url) => call('getVideoList', [url]);
  Future<List<MPage>> getPageList(String url) => call('getPageList', [url]);
  Future<String> getHtmlContent(String name, String url) =>
      call('getHtmlContent', [name, url]);
  Future<String> cleanHtmlContent(String html) =>
      call('cleanHtmlContent', [html]);

  void cancel() => _abort(StateError('Source call cancelled'));

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_commands != null && _pending.isEmpty) {
      try {
        final id = ++_nextId;
        final pending = Completer<Object?>();
        _pending[id] = pending;
        _commands!.send([id, '_close', const []]);
        await pending.future.timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
    _abort(StateError('Source worker disposed'));
  }

  void _abort(Object reason) {
    if (_ready?.isCompleted == false) _ready!.completeError(reason);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(reason);
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _responses?.close();
    _errors?.close();
    _exits?.close();
    _responses = null;
    _errors = null;
    _exits = null;
    _ready = null;
    _starting = null;
  }
}

class _WorkerInit {
  _WorkerInit(
    this.reply,
    this.token,
    this.source,
    this.code,
    this.language,
    this.preferences,
  );
  final SendPort reply;
  final RootIsolateToken? token;
  final MSource source;
  final String code;
  final MangayomiCodeLanguage language;
  final Map<String, dynamic> preferences;
}

Future<void> _runWorker(_WorkerInit init) async {
  if (init.token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(init.token!);
  }
  final commands = ReceivePort();
  init.reply.send(commands.sendPort);
  final js = init.language == MangayomiCodeLanguage.javascript
      ? JsSourceRuntime(init.source, init.code, preferences: init.preferences)
      : null;
  final dart = init.language == MangayomiCodeLanguage.dart
      ? DartSourceRuntime(init.source, init.code, preferences: init.preferences)
      : null;
  try {
    await for (final message in commands) {
      if (message is! List || message.length != 3) continue;
      final id = message[0];
      final operation = message[1] as String;
      final args = message[2] as List;
      try {
        if (operation == '_close') {
          init.reply.send([id, true, null]);
          break;
        }
        final result = await _invoke(js, dart, operation, args);
        init.reply.send([id, true, result]);
      } catch (error) {
        init.reply.send([id, false, error.toString()]);
      }
    }
  } finally {
    js?.dispose();
    dart?.dispose();
    commands.close();
  }
}

Future<Object?> _invoke(
  JsSourceRuntime? js,
  DartSourceRuntime? dart,
  String op,
  List args,
) {
  final runtime = js ?? dart!;
  return switch (op) {
    'getPopular' =>
      runtime is JsSourceRuntime
          ? runtime.getPopular(args[0] as int)
          : dart!.getPopular(args[0] as int),
    'getLatestUpdates' =>
      runtime is JsSourceRuntime
          ? runtime.getLatestUpdates(args[0] as int)
          : dart!.getLatestUpdates(args[0] as int),
    'search' =>
      runtime is JsSourceRuntime
          ? runtime.search(args[0] as String, args[1] as int, args[2] as List)
          : dart!.search(
              args[0] as String,
              args[1] as int,
              (args[2] as List)
                  .map((e) => dartFilter(Map<String, dynamic>.from(e as Map)))
                  .toList(),
            ),
    'getFilterList' =>
      runtime is JsSourceRuntime
          ? runtime
                .call<List<dynamic>>('getFilterList()')
                .then((items) => items.map(filterMap).toList())
          : dart!
                .invoke<List<dynamic>>('getFilterList')
                .then((items) => items.map(filterMap).toList()),
    'getSourcePreferences' =>
      runtime is JsSourceRuntime
          ? runtime
                .call<List<dynamic>>('getSourcePreferences()')
                .then((items) => items.map(preferenceMap).toList())
          : dart!
                .invoke<List<dynamic>>('getSourcePreferences')
                .then((items) => items.map(preferenceMap).toList()),
    'getDetail' =>
      runtime is JsSourceRuntime
          ? runtime.getDetail(args[0] as String)
          : dart!.getDetail(args[0] as String),
    'getVideoList' =>
      runtime is JsSourceRuntime
          ? runtime.getVideoList(args[0] as String)
          : dart!.getVideoList(args[0] as String),
    'getPageList' =>
      runtime is JsSourceRuntime
          ? runtime.getPageList(args[0] as String)
          : dart!.getPageList(args[0] as String),
    'getHtmlContent' =>
      runtime is JsSourceRuntime
          ? runtime.getHtmlContent(args[0] as String, args[1] as String)
          : dart!.getHtmlContent(args[0] as String, args[1] as String),
    'cleanHtmlContent' =>
      runtime is JsSourceRuntime
          ? runtime.cleanHtmlContent(args[0] as String)
          : dart!.cleanHtmlContent(args[0] as String),
    _ => Future.error(ArgumentError.value(op, 'operation')),
  };
}
