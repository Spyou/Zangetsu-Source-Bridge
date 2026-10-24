import 'package:flutter/material.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

void main() => runApp(const MaterialApp(home: RuntimeProof()));

class RuntimeProof extends StatefulWidget {
  const RuntimeProof({super.key});

  @override
  State<RuntimeProof> createState() => _RuntimeProofState();
}

class _RuntimeProofState extends State<RuntimeProof> {
  late final Future<String> result = _check();

  Future<String> _check() async {
    final source = MSource(
      id: 1,
      name: 'Proof',
      baseUrl: 'https://example.com',
    );
    final js = MangayomiRuntimeWorker(source, '''
class DefaultExtension extends MProvider {
  async getVideoList(url) { return [{url: url, originalUrl: url, quality: 'test'}]; }
  async getPageList(url) { return [url]; }
  async getHtmlContent(name, url) { return '<p>ready</p>'; }
}
''', MangayomiCodeLanguage.javascript);
    final dart = MangayomiRuntimeWorker(source, '''
import 'package:mangayomi/bridge_lib.dart';
class Proof extends MProvider {
  Proof(this.source);
  MSource source;
  Future<List<MVideo>> getVideoList(String url) async => [MVideo(url, 'test', url)];
  Future<List<String>> getPageList(String url) async => [url];
  Future<String> getHtmlContent(String name, String url) async => '<p>ready</p>';
}
Proof main(MSource source) => Proof(source);
''', MangayomiCodeLanguage.dart);
    try {
      if ((await js.getVideoList(
            'https://example.com/video',
          )).single.url.isEmpty ||
          (await js.getPageList(
            'https://example.com/page',
          )).single.url.isEmpty ||
          await js.getHtmlContent('', '') != '<p>ready</p>') {
        throw StateError('JavaScript worker returned invalid content');
      }
      if ((await dart.getVideoList(
            'https://example.com/video',
          )).single.url.isEmpty ||
          (await dart.getPageList(
            'https://example.com/page',
          )).single.url.isEmpty ||
          await dart.getHtmlContent('', '') != '<p>ready</p>') {
        throw StateError('Dart worker returned invalid content');
      }
      return 'JS and Dart workers: PASS';
    } finally {
      await js.dispose();
      await dart.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FutureBuilder<String>(
        future: result,
        builder: (context, snapshot) => Text(
          snapshot.hasError
              ? 'FAIL: ${snapshot.error}'
              : snapshot.data ?? 'Checking workers…',
        ),
      ),
    ),
  );
}
