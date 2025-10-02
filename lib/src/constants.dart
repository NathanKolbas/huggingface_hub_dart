// ignore_for_file: non_constant_identifier_names, constant_identifier_names

// Possible values for env variables

import 'package:huggingface_hub/huggingface_hub.dart';
import 'package:huggingface_hub/src/utils/platform/platform.dart';
import 'package:path/path.dart' as path;

const Set<String> ENV_VARS_TRUE_VALUES = {"1", "ON", "YES", "TRUE"};
final Set<String> ENV_VARS_TRUE_AND_AUTO_VALUES = ENV_VARS_TRUE_VALUES.union({"AUTO"});

bool _isTrue(String? value) {
  if (value == null) return false;

  return ENV_VARS_TRUE_VALUES.contains(value.toUpperCase());
}

int? _asInt(String? value) {
  if (value == null) return null;

  return int.tryParse(value);
}

// Constants for file downloads

const String PYTORCH_WEIGHTS_NAME = 'pytorch_model.bin';
const String TF2_WEIGHTS_NAME = 'tf_model.h5';
const String TF_WEIGHTS_NAME = 'model.ckpt';
const String FLAX_WEIGHTS_NAME = 'flax_model.msgpack';
const String CONFIG_NAME = 'config.json';
const String REPOCARD_NAME = 'README.md';
const double DEFAULT_ETAG_TIMEOUT = 10;
const int DEFAULT_DOWNLOAD_TIMEOUT = 10;
const double DEFAULT_REQUEST_TIMEOUT = 10;
const int DOWNLOAD_CHUNK_SIZE = 10 * 1024 * 1024;
const int HF_TRANSFER_CONCURRENCY = 100;
const int MAX_HTTP_DOWNLOAD_SIZE = 50 * 1000 * 1000 * 1000;  // 50 GB

// Constants for serialization

const String PYTORCH_WEIGHTS_FILE_PATTERN = 'pytorch_model{suffix}.bin';  // Unsafe pickle: use safetensors instead
const String SAFETENSORS_WEIGHTS_FILE_PATTERN = 'model{suffix}.safetensors';
const String TF2_WEIGHTS_FILE_PATTERN = 'tf_model{suffix}.h5';

// Git-related constants

const String DEFAULT_REVISION = 'main';

const String HUGGINGFACE_CO_URL_HOME = 'https://huggingface.co/';

const String _HF_DEFAULT_ENDPOINT = 'https://huggingface.co';
const String _HF_DEFAULT_STAGING_ENDPOINT = 'https://hub-ci.huggingface.co';
final String ENDPOINT = (Platform.environment['HF_ENDPOINT'] ?? _HF_DEFAULT_ENDPOINT)
    .replaceAll(RegExp(r'/+$'), ''); // Equal to python's `.rstrip('/')`
final String HUGGINGFACE_CO_URL_TEMPLATE = '$ENDPOINT/{repo_id}/resolve/{revision}/{filename}';

const String HUGGINGFACE_HEADER_X_REPO_COMMIT = 'X-Repo-Commit';
const String HUGGINGFACE_HEADER_X_LINKED_ETAG = 'X-Linked-Etag';
const String HUGGINGFACE_HEADER_X_LINKED_SIZE = 'X-Linked-Size';

const String REPO_ID_SEPARATOR = '--';
// ^ this substring is not allowed in repo_ids on hf.co
// and is the canonical one we use for serialization of repo ids elsewhere.


const String REPO_TYPE_DATASET = 'dataset';
const String REPO_TYPE_SPACE = 'space';
const String REPO_TYPE_MODEL = 'model';
const List<String?> REPO_TYPES = [null, REPO_TYPE_MODEL, REPO_TYPE_DATASET, REPO_TYPE_SPACE];

final Map<String, String> REPO_TYPES_URL_PREFIXES = {
  REPO_TYPE_DATASET: "datasets/",
  REPO_TYPE_SPACE: "spaces/",
};

/// Returns the path to the user's home directory.
String getUserHomePath() {
  // On web, there is no concept of a home directory
  if (kIsWeb) throw UnsupportedError('getUserHomePath is not supported on web');

  // Get the home directory from environment variables.
  // This is the most reliable way for desktop platforms.
  Map<String, String> envVars = Platform.environment;
  if (Platform.isMacOS || Platform.isLinux) {
    return envVars['HOME']!;
  } else if (Platform.isWindows) {
    return envVars['USERPROFILE']!;
  } else if (Platform.isAndroid || Platform.isIOS) {
    return HuggingfaceHub.defaultMobileHomeDir;
  }

  throw UnsupportedError('getUserHomePath is not supported on this platform');
}

// default cache
final String defaultHome = path.join(getUserHomePath(), '.cache');
final String HF_HOME = Platform.environment["HF_HOME"] ?? path.join(Platform.environment["XDG_CACHE_HOME"] ?? defaultHome, 'huggingface');

final String defaultCachePath = path.join(HF_HOME, 'hub');

// Legacy env variables
final String _huggingfaceHubCache = Platform.environment["HUGGINGFACE_HUB_CACHE"] ?? defaultCachePath;

// New env variables
final String HF_HUB_CACHE = Platform.environment["HF_HUB_CACHE"] ?? _huggingfaceHubCache;

final String HF_TOKEN_PATH = Platform.environment["HF_TOKEN_PATH"] ?? path.join(HF_HOME, 'token');

// Disable warning on machines that do not support symlinks (e.g. Windows non-developer)
final bool HF_HUB_DISABLE_SYMLINKS_WARNING = _isTrue(Platform.environment['HF_HUB_DISABLE_SYMLINKS_WARNING']);

// Disable sending the cached token by default is all HTTP requests to the Hub
final bool HF_HUB_DISABLE_IMPLICIT_TOKEN = _isTrue(Platform.environment['HF_HUB_DISABLE_IMPLICIT_TOKEN']);

// Enable fast-download using external dependency "hf_transfer"
// See:
// - https://pypi.org/project/hf-transfer/
// - https://github.com/huggingface/hf_transfer (private)
final bool HF_HUB_ENABLE_HF_TRANSFER = _isTrue(Platform.environment['HF_HUB_ENABLE_HF_TRANSFER']);

// Used to override the etag timeout on a system level
final int HF_HUB_ETAG_TIMEOUT = _asInt(Platform.environment["HF_HUB_ETAG_TIMEOUT"]) ?? DEFAULT_ETAG_TIMEOUT.toInt();

// Used to override the get request timeout on a system level
final int HF_HUB_DOWNLOAD_TIMEOUT = _asInt(Platform.environment["HF_HUB_DOWNLOAD_TIMEOUT"]) ?? DEFAULT_DOWNLOAD_TIMEOUT;

// Allows to add information about the requester in the user-agent (eg. partner name)
final String? HF_HUB_USER_AGENT_ORIGIN = Platform.environment['HF_HUB_USER_AGENT_ORIGIN'];

// Xet constants
const String HUGGINGFACE_HEADER_X_XET_ENDPOINT = 'X-Xet-Cas-Url';
const String HUGGINGFACE_HEADER_X_XET_ACCESS_TOKEN = 'X-Xet-Access-Token';
const String HUGGINGFACE_HEADER_X_XET_EXPIRATION = 'X-Xet-Token-Expiration';
const String HUGGINGFACE_HEADER_X_XET_HASH = 'X-Xet-Hash';
const String HUGGINGFACE_HEADER_X_XET_REFRESH_ROUTE = 'X-Xet-Refresh-Route';
const String HUGGINGFACE_HEADER_LINK_XET_AUTH_KEY = 'xet-auth';

final bool HF_HUB_DISABLE_XET = _isTrue(Platform.environment['HF_HUB_DISABLE_XET']);
