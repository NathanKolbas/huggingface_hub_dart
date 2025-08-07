import 'dart:io';
import 'package:huggingface_hub/src/constants.dart' as constants;

/// Get token if user is logged in.
///
/// Note: in most cases, you should use [`huggingface_hub.utils.build_hf_headers`] instead. This method is only useful
///       if you want to retrieve the token for other purposes than sending an HTTP request.
///
/// Token is retrieved in priority from the `HF_TOKEN` environment variable. Otherwise, we read the token file located
/// in the Hugging Face home folder. Returns None if user is not logged in. To log in, use [`login`] or
/// `huggingface-cli login`.
///
/// Returns:
///     `str` or `None`: The token, `None` if it doesn't exist.
Future<String?> getToken() async {
  return _getTokenFromEnvironment() ?? await _getTokenFromFile();
}

String? _getTokenFromEnvironment() {
  // `HF_TOKEN` has priority (keep `HUGGING_FACE_HUB_TOKEN` for backward compatibility)
  return _cleanToken(Platform.environment['HF_TOKEN'] ?? Platform.environment['HUGGING_FACE_HUB_TOKEN']);
}

Future<String?> _getTokenFromFile() async {
  // try:
  // return _clean_token(Path(constants.HF_TOKEN_PATH).read_text())
  // except FileNotFoundError:
  // return None

  try {
    return _cleanToken(await File(constants.HF_TOKEN_PATH).readAsString());
  } catch (_) {
    return null;
  }
}

// Clean token by removing trailing and leading spaces and newlines.
//
// If token is an empty string, return None.
String? _cleanToken(String? token) {
  if (token == null) return null;

  final cleanedToken = token.replaceAll(r'\r', '').replaceAll(r'\n', '').trim();
  return cleanedToken.isEmpty ? null : cleanedToken;
}
