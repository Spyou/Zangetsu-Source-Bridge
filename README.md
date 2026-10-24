# Zangetsu Source Bridge

A Flutter package for running Mangayomi-compatible JavaScript and Dart extensions as video, manga, and novel sources.

The package reads extension repository indexes, installs source code locally, and runs each source in its own worker with timeouts and cancellation. It maps results into shared video, manga-page, and chapter-text models.

## Development

Run the package checks from this directory:

```sh
flutter test
flutter analyze
```

The live source checks are opt-in because source websites can block automated requests or change their APIs:

```sh
flutter test --dart-define=RUN_LIVE_EXTENSION_TESTS=true test/proof_sources_test.dart
```

The `harness/` app smoke-checks both runtime workers on Android and iOS. It displays `JS and Dart workers: PASS` when its sample calls finish.
