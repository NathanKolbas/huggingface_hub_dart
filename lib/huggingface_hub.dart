export 'src/_auth.dart';
export 'src/_headers.dart';
export 'src/_http.dart';
export 'src/_local_folder.dart';
export 'src/_runtime.dart';
export 'src/_snapshot_download.dart';
export 'src/_space_api.dart';
export 'src/constants.dart';
export 'src/errors.dart';
export 'src/file_download.dart';
export 'src/hf_api.dart';
export 'src/repocard_data.dart';

export 'src/utils/_fixes.dart';
export 'src/utils/_pagination.dart';
export 'src/utils/_paths.dart';
export 'src/utils/_xet.dart';
export 'src/utils/python_to_dart.dart';

import 'dart:io';

import 'package:hf_xet/hf_xet.dart';
import 'package:path_provider/path_provider.dart';

import 'huggingface_hub.dart';

class HuggingfaceHub {
  static final HuggingfaceHub _instance = HuggingfaceHub._internal();

  factory HuggingfaceHub() => _instance;

  HuggingfaceHub._internal();

  bool _initialized = false;

  /// If huggingface_hub is initialized. Typically you don't need this and can
  /// just call [ensureInitialized] directly without checking if initialized
  /// prior.
  static bool get initialized => HuggingfaceHub._instance._initialized;

  /// Make sure huggingface_hub is initialized.
  ///
  /// If [throwOnFail] is set to true then an exception will be thrown if
  /// initialization fails. By default this is false.
  ///
  /// Returns [bool] whether or not initialization was successful. If
  /// [throwOnFail] is true then you must catch the error.
  static Future<bool> ensureInitialized({bool throwOnFail = false}) async {
    if (HuggingfaceHub._instance._initialized) return true;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final mobileHomeDir = await getApplicationDocumentsDirectory();
        HuggingfaceHub._instance._defaultMobileHomeDir = mobileHomeDir.path;
      }

      await HfXet.ensureInitialized(
        throwOnFail: throwOnFail,
        huggingfaceHubVersion: getHfHubVersion(),
        huggingfaceHome: () => HF_HOME,
      );

      HuggingfaceHub._instance._initialized = true;

      return HuggingfaceHub._instance._initialized;
    } catch (_) {
      if (throwOnFail) {
        rethrow;
      }
    }

    return HuggingfaceHub._instance._initialized;
  }

  String? _defaultMobileHomeDir;

  static String get defaultMobileHomeDir {
    final homeDir = HuggingfaceHub._instance._defaultMobileHomeDir;
    if (homeDir == null) {
      throw StateError('You must call HuggingfaceHub.ensureInitialized '
          'first to be able to access the default mobile home directory.');
    }

    return homeDir;
  }
}
