import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    final entries = jsonDecode(
      await rootBundle.loadString('assets/native_licenses.json'),
    ) as List;
    for (final entry in entries.cast<Map<String, dynamic>>()) {
      yield LicenseEntryWithLineBreaks([
        '${entry['name']} ${entry['version']}',
      ], entry['text'] as String);
    }
  });
}
