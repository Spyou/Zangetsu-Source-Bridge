import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Reuses the app's WebView clearance only for sources that declare protection.
class MangayomiHttpClient extends http.BaseClient {
  MangayomiHttpClient({required this.protected, http.Client? inner})
    : _inner = inner ?? http.Client();

  final bool protected;
  final http.Client _inner;
  static const _channel = MethodChannel('zangetsu/mihon');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (protected) {
      try {
        final headers = await _channel.invokeMapMethod<String, String>(
          'imageCookie',
          {'url': request.url.toString()},
        );
        final cookie = headers?['Cookie'];
        if (cookie != null && cookie.isNotEmpty) {
          request.headers['Cookie'] = cookie;
          final userAgent = headers?['User-Agent'];
          if (userAgent != null) request.headers['User-Agent'] = userAgent;
        }
      } on MissingPluginException {
        // The native solver is Android-only; ordinary requests still work.
      } on PlatformException {
        // A missing cookie must not prevent the first request to a source.
      }
    }
    final response = await _inner.send(request);
    if (protected &&
        (response.headers['cf-mitigated'] == 'challenge' ||
            ((response.statusCode == 403 || response.statusCode == 503) &&
                response.headers['server']?.toLowerCase().contains(
                      'cloudflare',
                    ) ==
                    true))) {
      await response.stream.drain<void>();
      throw StateError('Cloudflare challenge at ${request.url}');
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
