import 'dart:io';

import 'package:hf_xet/hf_xet.dart';
import 'package:huggingface_hub/src/constants.dart' as constants;

/// TODO: This isn't *really* a thing in Dart...
bool isPackageAvailable(String packageName) {
  // return _get_version(package_name) != "N/A"
  return false;
}

// Dart
String getDartVersion() => Platform.version;

// Huggingface Hub
// TODO: Generate this from pubspec.yaml
String getHfHubVersion() => '0.0.1';

// xet
bool isXetAvailable() {
  // since hf_xet is automatically used if available, allow explicit disabling via environment variable
  if (constants.HF_HUB_DISABLE_XET) return false;

  return HfXet.isSupported();
}
