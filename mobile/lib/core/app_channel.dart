import 'package:flutter/foundation.dart';

/// Canal de origem do cliente (`web`, `android`, `ios`, `unknown`) para o registo no servidor.
String resolveAppChannel() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    default:
      return 'unknown';
  }
}
