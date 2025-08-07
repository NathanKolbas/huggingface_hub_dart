// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:io' show Platform, File, FileSystemEntity, FileSystemEntityType, Directory, FileMode, FileSystemException, Link, RandomAccessFile;
import 'dart:typed_data' show Uint8List;

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:huggingface_hub/src/constants.dart' as constants;
import 'package:huggingface_hub/src/errors.dart';
import 'package:huggingface_hub/src/utils/_fixes.dart';
import 'package:huggingface_hub/src/utils/python_to_dart.dart';
import 'package:uuid/uuid.dart';

import '_headers.dart';

import 'package:path/path.dart' as path;

import '_http.dart';
import '_local_folder.dart';
import '_runtime.dart';
import 'utils/_xet.dart';

final uuid = Uuid();

// Return value when trying to load a file from cache but the file does not exist in the distant repo.
final Object _CACHED_NO_EXIST = Object();

// Regex to get filename from a "Content-Disposition" header for CDN-served files
final RegExp HEADER_FILENAME_PATTERN = RegExp(r'filename="(.*?)"');

// Regex to check if the revision IS directly a commit_hash
final REGEX_COMMIT_HASH = RegExp(r'^[0-9a-f]{40}$');

// Regex to check if the file etag IS a valid sha256
final REGEX_SHA256 = RegExp(r'^[0-9a-f]{64}$');

final Map<String, bool> _areSymlinksSupportedInDir = {};

/// Return whether the symlinks are supported on the machine.
///
/// Since symlinks support can change depending on the mounted disk, we need to check
/// on the precise cache folder. By default, the default HF cache directory is checked.
///
/// Args:
/// cache_dir (`str`, `Path`, *optional*):
/// Path to the folder where cached files are stored.
///
/// Returns: [bool] Whether symlinks are supported in the directory.
Future<bool> areSymlinksSupported([String? cacheDir]) async {
  // Defaults to HF cache
  cacheDir ??= constants.HF_HUB_CACHE;
  // TODO: Might need this:
  // cache_dir = str(Path(cache_dir).expanduser().resolve())  # make it unique

  // Check symlink compatibility only once (per cache directory) at first time use
  if (!_areSymlinksSupportedInDir.containsKey(cacheDir)) {
    _areSymlinksSupportedInDir[cacheDir] = true;

    await Directory(cacheDir).create(recursive: true);
    await SoftTemporaryDirectory(cacheDir, (tempdir) async {
      final srcPath = path.join(tempdir.path, 'dummy_file_src');
      await File(srcPath).create(recursive: true);
      final dstPath = path.join(tempdir.path, 'dummy_file_dst');

      // Relative source path as in `_create_symlink``
      // Dart needs the paths to be absolute otherwise the relative path is from the executed dart file
      // final relativeSrc = path.relative(srcPath, from: path.dirname(dstPath));
      try {
        await Link(dstPath).create(srcPath, recursive: true);
      } on FileSystemException catch (e) {
        // Likely running on Windows
        _areSymlinksSupportedInDir[cacheDir!] = false;

        if (!constants.HF_HUB_DISABLE_SYMLINKS_WARNING) {
          String message = '`huggingface_hub` cache-system uses symlinks by default to'
              ' efficiently store duplicated files but your machine does not'
              ' support them in $cacheDir. Caching files will still work'
              ' but in a degraded version that might require more space on'
              ' your disk. This warning can be disabled by setting the'
              ' `HF_HUB_DISABLE_SYMLINKS_WARNING` environment variable. For'
              ' more details, see'
              ' https://huggingface.co/docs/huggingface_hub/how-to-cache#limitations.';
          if (Platform.isWindows) {
            message += '\nTo support symlinks on Windows, you either need to'
                ' activate Developer Mode or to run Python as an'
                ' administrator. In order to activate developer mode,'
                ' see this article:'
                ' https://docs.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development';
          }
          print(message);
        }
      }
    });
  }

  return _areSymlinksSupportedInDir[cacheDir]!;
}

/// Data structure containing information about a file versioned on the Hub.
///
/// Returned by [`get_hf_file_metadata`] based on a URL.
///
/// Args:
/// commit_hash (`str`, *optional*):
/// The commit_hash related to the file.
/// etag (`str`, *optional*):
/// Etag of the file on the server.
/// location (`str`):
/// Location where to download the file. Can be a Hub url or not (CDN).
/// size (`size`):
/// Size of the file. In case of an LFS file, contains the size of the actual
/// LFS file, not the pointer.
/// xet_file_data (`XetFileData`, *optional*):
/// Xet information for the file. This is only set if the file is stored using Xet storage.
// @dataclass(frozen=True)
class HfFileMetadata {
  String? commitHash;

  String? etag;

  String location;

  int? size;

  XetFileData? xetFileData;

  HfFileMetadata({
    required this.location,
    this.commitHash,
    this.etag,
    this.size,
    this.xetFileData,
  });
}

/// Construct the URL of a file from the given information.
///
/// The resolved address can either be a huggingface.co-hosted url, or a link to
/// Cloudfront (a Content Delivery Network, or CDN) for large files which are
/// more than a few MBs.
///
/// Args:
/// repo_id (`str`):
/// A namespace (user or an organization) name and a repo name separated
/// by a `/`.
/// filename (`str`):
/// The name of the file in the repo.
/// subfolder (`str`, *optional*):
/// An optional value corresponding to a folder inside the repo.
/// repo_type (`str`, *optional*):
/// Set to `"dataset"` or `"space"` if downloading from a dataset or space,
/// `None` or `"model"` if downloading from a model. Default is `None`.
/// revision (`str`, *optional*):
/// An optional Git revision id which can be a branch name, a tag, or a
/// commit hash.
///
/// Example:
///
/// ```python
/// >>> from huggingface_hub import hf_hub_url
///
/// >>> hf_hub_url(
/// ...     repo_id="julien-c/EsperBERTo-small", filename="pytorch_model.bin"
/// ... )
/// 'https://huggingface.co/julien-c/EsperBERTo-small/resolve/main/pytorch_model.bin'
/// ```
///
/// <Tip>
///
/// Notes:
///
/// Cloudfront is replicated over the globe so downloads are way faster for
/// the end user (and it also lowers our bandwidth costs).
///
/// Cloudfront aggressively caches files by default (default TTL is 24
/// hours), however this is not an issue here because we implement a
/// git-based versioning system on huggingface.co, which means that we store
/// the files on S3/Cloudfront in a content-addressable way (i.e., the file
/// name is its hash). Using content-addressable filenames means cache can't
/// ever be stale.
///
/// In terms of client-side caching from this library, we base our caching
/// on the objects' entity tag (`ETag`), which is an identifier of a
/// specific version of a resource [1]_. An object's ETag is: its git-sha1
/// if stored in git, or its sha256 if stored in git-lfs.
///
/// </Tip>
///
/// References:
///
/// -  [1] https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/ETag
String hfHubUrl(
  String repoId,
  String filename,
  {
    String? subfolder,
    String? repoType,
    String? revision,
    String? endpoint,
  }
) {
  if (subfolder == '') {
    subfolder = null;
  }
  if (subfolder != null) {
    filename = '$subfolder/$filename';
  }

  if (constants.REPO_TYPES_URL_PREFIXES.containsKey(repoType)) {
    repoId = constants.REPO_TYPES_URL_PREFIXES[repoType]! + repoId;
  }

  revision ??= constants.DEFAULT_REVISION;

  String url = constants.HUGGINGFACE_CO_URL_TEMPLATE
    .replaceFirst('{filename}', Uri.encodeFull(filename))
    .replaceFirst('{revision}', Uri.encodeFull(revision).replaceAll('/', '%2F'))
    .replaceFirst('{repo_id}', repoId);
  if (endpoint != null && url.startsWith(constants.ENDPOINT)) {
    url = endpoint + url.substring(constants.ENDPOINT.length);
  }
  return url;
}

/// Wrapper around requests methods to follow relative redirects if `follow_relative_redirects=True` even when
/// `allow_redirection=False`.
///
/// A backoff mechanism retries the HTTP call on 429, 503 and 504 errors.
///
/// Args:
///     method (`str`):
///         HTTP method, such as 'GET' or 'HEAD'.
///     url (`str`):
///         The URL of the resource to fetch.
///     follow_relative_redirects (`bool`, *optional*, defaults to `False`)
///         If True, relative redirection (redirection to the same site) will be resolved even when `allow_redirection`
///         kwarg is set to False. Useful when we want to follow a redirection to a renamed repository without
///         following redirection to a CDN.
///     **params (`dict`, *optional*):
///         Params to pass to `requests.request`.
Future<Response> _requestWrapper({
  required method,
  required String url,
  bool followRelativeRedirects = false,
  Map<String, dynamic> params = const {},
  Options? dioOptions,
}) async {
  // Recursively follow relative redirects
  if (followRelativeRedirects) {
    final response = await _requestWrapper(
      method: method,
      url: url,
      followRelativeRedirects: false,
      params: params,
      dioOptions: dioOptions,
    );

    // If redirection, we redirect only relative paths.
    // This is useful in case of a renamed repository.
    final statusCode = response.statusCode!;
    if (300 <= statusCode && statusCode <= 399) {
      final Uri parsedTarget = Uri.parse(response.headers.value('Location')!);

      if (parsedTarget.host.isEmpty) {
        // This means it is a relative 'location' headers, as allowed by RFC 7231.
        // (e.g. '/path/to/resource' instead of 'http://domain.tld/path/to/resource')
        // We want to follow this relative redirect !
        //
        // Highly inspired by `resolve_redirects` from requests library.
        // See https://github.com/psf/requests/blob/main/requests/sessions.py#L159

        // Create the new, absolute URL by replacing the path of the original URL
        // with the path from the relative redirect.
        final Uri nextUri = Uri.parse(url).replace(
          path: parsedTarget.path,
          query: parsedTarget.query, // Also preserve query parameters from the redirect
        );
        final String nextUrl = nextUri.toString();

        return await _requestWrapper(
          method: method,
          url: nextUrl,
          followRelativeRedirects: true,
          params: params,
          dioOptions: dioOptions,
        );
      }
    }
    return response;
  }

  // Perform request and return if status_code is not in the retry list.
  final (response, raiseForStatus) = await httpBackoff(
    method: method,
    url: url,
    kwargs: params,
    retryOnExceptions: [],
    retryOnStatusCodes: [429],
    dioOptions: dioOptions,
  );
  hfRaiseForStatus(response, raiseForStatus);
  return response;
}

/// Get the length of the file from the HTTP response headers.
///
/// This function extracts the file size from the HTTP response headers, either from the
/// `Content-Range` or `Content-Length` header, if available (in that order).
/// The HTTP response object containing the headers.
/// `int` or `None`: The length of the file in bytes if the information is available,
/// otherwise `None`.
///
/// Args:
/// response (`requests.Response`):
/// The HTTP response object.
///
/// Returns:
/// `int` or `None`: The length of the file in bytes, or None if not available.
int? _getFileLengthFromHttpResponse(Response response) {
  String? contentRange = response.headers.value('Content-Range');
  if (contentRange != null) return int.parse(contentRange.split('/').last);

  contentRange = response.headers.value('Content-Range');
  if (contentRange != null) return int.parse(contentRange);

  return null;
}

/// Download a remote file. Do not gobble up errors, and will return errors tailored to the Hugging Face Hub.
///
/// If ConnectionError (SSLError) or ReadTimeout happen while streaming data from the server, it is most likely a
/// transient error (network outage?). We log a warning message and try to resume the download a few times before
/// giving up. The method gives up after 5 attempts if no new data has being received from the server.
///
/// Args:
///     url (`str`):
///         The URL of the file to download.
///     temp_file (`BinaryIO`):
///         The file-like object where to save the file.
///     proxies (`dict`, *optional*):
///         Dictionary mapping protocol to the URL of the proxy passed to `requests.request`.
///     resume_size (`int`, *optional*):
///         The number of bytes already downloaded. If set to 0 (default), the whole file is download. If set to a
///         positive number, the download will resume at the given position.
///     headers (`dict`, *optional*):
///         Dictionary of HTTP Headers to send with the request.
///     expected_size (`int`, *optional*):
///         The expected size of the file to download. If set, the download will raise an error if the size of the
///         received content is different from the expected one.
///     displayed_filename (`str`, *optional*):
///         The filename of the file that is being downloaded. Value is used only to display a nice progress bar. If
///         not set, the filename is guessed from the URL or the `Content-Disposition` header.
Future<void> httpGet(
    String url,
    RandomAccessFile tempFile,
    {
      Map? proxies,
      int resumeSize = 0,
      Map<String, dynamic>? headers,
      int? expectedSize,
      String? displayedFilename,
      int nbRetries = 5,
      // TODO: Come up with some kind of alternative for this:
      // _tqdm_bar: Optional[tqdm] = None,
    }
) async {
  // If the file is already fully downloaded, we don't need to download it again.
  if (expectedSize != null && resumeSize == expectedSize) return;

  final hasCustomRangeHeader = headers != null && [for (final h in headers.keys) h.toLowerCase() == 'range'].contains(true);
  final hfTransfer = null;
  if (constants.HF_HUB_ENABLE_HF_TRANSFER) {
    if (resumeSize != 0) {
      print("'hf_transfer' does not support `resume_size`: falling back to regular download method");
    } else if (proxies != null) {
      print("'hf_transfer' does not support `proxies`: falling back to regular download method");
    } else if (hasCustomRangeHeader) {
      print("'hf_transfer' ignores custom 'Range' headers; falling back to regular download method");
    } else {
      // TODO: hf_transfer needs to be implemented. Basically the same thing as xet:
      // https://github.com/huggingface/hf_transfer
      throw UnimplementedError(
          "Fast download using 'hf_transfer' is enabled"
          " (HF_HUB_ENABLE_HF_TRANSFER=1) but 'hf_transfer' package is not"
          " available in your environment. Try `pip install hf_transfer`."
          " JK THIS IS DART LOL - NEEDS TO BE IMPLEMENTED..."
      );
    }
  }

  final initialHeaders = headers;
  // WARNING: Dart does not have a deepcopy like in python so hopefully this will do for now:
  headers = headers != null ? {...headers} : {};
  if (resumeSize > 0) {
    headers['Range'] = adjustRangeHeader(headers['Range'], resumeSize);
  } else if ((expectedSize != null && expectedSize != 0) && expectedSize > constants.MAX_HTTP_DOWNLOAD_SIZE) {
    // Any files over 50GB will not be available through basic http request.
    // Setting the range header to 0-0 will force the server to return the file size in the Content-Range header.
    // Since hf_transfer splits the download into chunks, the process will succeed afterwards.
    if (hfTransfer != null) {
      headers['Range'] = 'bytes=0-0';
    } else {
      throw ArgumentError(
          "The file is too large to be downloaded using the regular download method. Use `hf_transfer` or `hf_xet` instead."
          " Try `pip install hf_transfer` or `pip install hf_xet`."
      );
    }
  }

  final Response r = await _requestWrapper(
    method: 'GET',
    url: url,
    dioOptions: Options(
      responseType: ResponseType.stream,
      headers: headers,
      receiveTimeout: Duration(seconds: constants.HF_HUB_DOWNLOAD_TIMEOUT),
      // TODO: Figure out proxies: https://pub.dev/packages/dio#using-proxy
      // proxies: proxies,
    ),
  );

  // TODO: Is this needed?
  // hfRaiseForStatus(r, raiseForStatus);
  final contentLength = _getFileLengthFromHttpResponse(r);

  // NOTE: 'total' is the total number of bytes to download, not the number of bytes in the file.
  //       If the file is compressed, the number of bytes in the saved file will be higher than 'total'.
  final total = contentLength != null ? resumeSize + contentLength : null;

  if (displayedFilename == null) {
    displayedFilename = url;
    final String? contentDisposition = r.headers.value('Content-Disposition');
    if (contentDisposition != null) {
      final Match? match = HEADER_FILENAME_PATTERN.firstMatch(contentDisposition);
      if (match != null && match.groupCount > 0) {
        // Means file is on CDN
        displayedFilename = match.group(1);
      }
    }
  }

  // Truncate filename if too long to display
  if (displayedFilename!.length > 40) {
    displayedFilename = '(…)${displayedFilename.substring(displayedFilename.length - 40)}';
  }

  final String consistencyErrorMessage = 'Consistency check failed: file should be of size $expectedSize but has size'
      ' {{actual_size}} ($displayedFilename).\nThis is usually due to network issues while downloading the file.'
      ' Please retry with `force_download=True`.';
  // progress_cm = _get_progress_bar_context(
  //   desc=displayed_filename,
  //   log_level=logger.getEffectiveLevel(),
  //   total=total,
  //   initial=resume_size,
  //   name="huggingface_hub.http_get",
  //   _tqdm_bar=_tqdm_bar,
  // )

  // with progress_cm as progress:
  if (hfTransfer != null && total != null && total > 5 * constants.DOWNLOAD_CHUNK_SIZE) {
    // try {
    //   hf_transfer.download();
    // }
    throw UnimplementedError('Fast download using "hf_transfer" is not implemented yet.');
    return;
  }
  int newResumeSize = resumeSize;
  try {
    final Stream<Uint8List> stream = (r.data as ResponseBody).stream;

    await for (final chunk in stream) {
      // progress.update(len(chunk))
      await tempFile.writeFrom(chunk);
      newResumeSize += chunk.length;
      // Some data has been downloaded from the server so we reset the number of retries.
      nbRetries = 5;
    }

    await tempFile.flush();
  } on DioException catch (e) {
    if (e.type != DioExceptionType.connectionError && e.type != DioExceptionType.receiveTimeout) {
      return;
    }

    // If ConnectionError (SSLError) or ReadTimeout happen while streaming data from the server, it is most likely
    // a transient error (network outage?). We log a warning message and try to resume the download a few times
    // before giving up. Tre retry mechanism is basic but should be enough in most cases.
    if (nbRetries <= 0) {
      print('Error while downloading from $url: $e\nMax retries exceeded.');
      rethrow;
    }
    print('Error while downloading from $url: $e\nTrying to resume download...');
    await Future.delayed(Duration(seconds: 1));
    resetSessions(); // In case of SSLError it's best to reset the shared requests.Session objects
    return await httpGet(
      url,
      tempFile,
      proxies: proxies,
      resumeSize: newResumeSize,
      headers: initialHeaders,
      expectedSize: expectedSize,
      nbRetries: nbRetries - 1,
    );
  }

  final fileSize = await tempFile.length();
  if (expectedSize != null && expectedSize != fileSize) {
    throw StateError(consistencyErrorMessage.replaceAll(r'{{actual_size}}', fileSize.toString()));
  }
}

/// This is currently not implemented. Xet needs to be added to Dart. You can find
/// the project here: https://github.com/huggingface/xet-core. Basically, bindins
/// need to be created for the Rust library and Dart. No idea if this will *just work*
/// cross-platform. Probably can use https://pub.dev/packages/flutter_rust_bridge to
/// make this work.
void xetGet({
  required String incompletePath,
  required XetFileData xetFileData,
  required Map<String, String> headers,
  int? expectedSize,
  String? displayedFilename,
  // TODO: Come up with some kind of alternative for this:
  // _tqdm_bar: Optional[tqdm] = None,
}) {
  // TODO: This needs to be implemented
}

/// Normalize ETag HTTP header, so it can be used to create nice filepaths.
///
/// The HTTP spec allows two forms of ETag:
/// ETag: W/"<etag_value>"
/// ETag: "<etag_value>"
///
/// For now, we only expect the second form from the server, but we want to be future-proof so we support both. For
/// more context, see `TestNormalizeEtag` tests and https://github.com/huggingface/huggingface_hub/pull/1428.
///
/// Args:
/// etag (`str`, *optional*): HTTP header
///
/// Returns:
/// `str` or `None`: string that can be used as a nice directory name.
/// Returns `None` if input is None.
String? _normalizeEtag(String? etag) => etag
    ?.replaceAll(RegExp(r'^[W/]+'), '') // Equal to python's `.lstrip("W/")`
    .replaceAll(RegExp(r'^"+|"+$'), ''); // Equal to python's `.strip('"')`

/// Create a symbolic link named dst pointing to src.
///
/// By default, it will try to create a symlink using a relative path. Relative paths have 2 advantages:
/// - If the cache_folder is moved (example: back-up on a shared drive), relative paths within the cache folder will
/// not break.
/// - Relative paths seems to be better handled on Windows. Issue was reported 3 times in less than a week when
/// changing from relative to absolute paths. See https://github.com/huggingface/huggingface_hub/issues/1398,
/// https://github.com/huggingface/diffusers/issues/2729 and https://github.com/huggingface/transformers/pull/22228.
/// NOTE: The issue with absolute paths doesn't happen on admin mode.
/// When creating a symlink from the cache to a local folder, it is possible that a relative path cannot be created.
/// This happens when paths are not on the same volume. In that case, we use absolute paths.
///
///
/// The result layout looks something like
/// └── [ 128]  snapshots
/// ├── [ 128]  2439f60ef33a0d46d85da5001d52aeda5b00ce9f
/// │   ├── [  52]  README.md -> ../../../blobs/d7edf6bd2a681fb0175f7735299831ee1b22b812
/// │   └── [  76]  pytorch_model.bin -> ../../../blobs/403450e234d65943a7dcf7e05a771ce3c92faa84dd07db4ac20f592037a1e4bd
///
/// If symlinks cannot be created on this platform (most likely to be Windows), the workaround is to avoid symlinks by
/// having the actual file in `dst`. If it is a new file (`new_blob=True`), we move it to `dst`. If it is not a new file
/// (`new_blob=False`), we don't know if the blob file is already referenced elsewhere. To avoid breaking existing
/// cache, the file is duplicated on the disk.
///
/// In case symlinks are not supported, a warning message is displayed to the user once when loading `huggingface_hub`.
/// The warning message can be disabled with the `DISABLE_SYMLINKS_WARNING` environment variable.
Future<void> _createSymlink(String src, String dst, {bool newBlob = false}) async {
  try {
    await File(dst).delete();
  } on FileSystemException catch (_) {}

  // abs_src = os.path.abspath(os.path.expanduser(src))
  final absSrc = path.absolute(src);
  // abs_dst = os.path.abspath(os.path.expanduser(dst))
  final absDst = path.absolute(dst);
  // abs_dst_folder = os.path.dirname(abs_dst)
  // final absDstFolder = path.dirname(absDst);

  // Use relative_dst in priority
  // Dart needs the paths to be absolute otherwise the relative path is from the executed dart file
  // String? relativeSrc;
  // try {
  //   relativeSrc = path.relative(absSrc, from: absDstFolder);
  // } catch (_) {
  //   // Raised on Windows if src and dst are not on the same volume. This is the case when creating a symlink to a
  //   // local_dir instead of within the cache directory.
  //   // See https://docs.python.org/3/library/os.path.html#os.path.relpath
  // }

  bool supportSymlinks = false;
  try {
    final commonpath = commonPath([absSrc, absDst]);
    supportSymlinks = await areSymlinksSupported(commonpath);
  } catch (e) {
    // TODO: Need to figure out what errors are thrown to catch like in python
    rethrow;
  }

  // Symlinks are supported => let's create a symlink.
  if (supportSymlinks) {
    // Dart needs the paths to be absolute otherwise the relative path is from the executed dart file
    // final srcRelOrAbs = relativeSrc ?? absSrc;
    print('Creating pointer from $absSrc to $absDst');
    try {
      await Link(absDst).create(absSrc, recursive: true);
      return;
    } on FileSystemException catch (e) {
      // TODO: Need to figure out what errors are thrown to catch like in python
      rethrow;
    }
  }

  // Symlinks are not supported => let's move or copy the file.
  if (newBlob) {
    print('Symlink not supported. Moving file from $absSrc to $absDst');
    // shutil.move(abs_src, abs_dst, copy_function=_copy_no_matter_what)
    moveFile(absSrc, absDst);
  } else {
    print('Symlink not supported. Copying file from $absSrc to $absDst');
    await File(absSrc).copy(absDst);
  }
}

/// Cache reference between a revision (tag, branch or truncated commit hash) and the corresponding commit hash.
///
/// Does nothing if `revision` is already a proper `commit_hash` or reference is already cached.
Future<void> _cacheCommitHashForSpecificRevision(String storageFolder, String revision, String commitHash) async {
  if (revision != commitHash) {
    final refPath = path.join(storageFolder, 'refs', revision);
    final refFile = File(refPath);
    final refDir = Directory(path.dirname(refPath));

    await refDir.create(recursive: true);

    if (!await refFile.exists() || await refFile.readAsString() != commitHash) {
      // Update ref only if has been updated. Could cause useless error in case
      // repo is already cached and user doesn't have write access to cache folder.
      // See https://github.com/huggingface/huggingface_hub/issues/1216.
      await refFile.writeAsString(commitHash);
    }
  }
}

/// Return a serialized version of a hf.co repo name and type, safe for disk storage
/// as a single non-nested folder.
///
/// Example: models--julien-c--EsperBERTo-small
String repoFolderName({
  required String repoId,
  required String repoType,
}) {
  // remove all `/` occurrences to correctly convert repo to directory name
  final parts = ['${repoType}s', ...repoId.split('/')];
  return parts.join(constants.REPO_ID_SEPARATOR);
}

/// Check disk usage and log a warning if there is not enough disk space to download the file.
///
/// Args:
///     expected_size (`int`):
///         The expected size of the file in bytes.
///     target_dir (`str`):
///         The directory where the file will be stored after downloading.
///
/// TODO: This needs to be implemented. Dart doesn't have a way, at the time of writing, to do
/// this via it's API. This might be a good starting point: https://pub.dev/packages/disk_space_2
void _checkDiskSpace(int expectedSize, String targetDir) {
  // In Dart, there isn't a direct equivalent to Python's `shutil.disk_usage` for getting
  // disk space. This functionality typically requires platform-specific implementations
  // or external packages. For a cross-platform solution, you might need to use FFI
  // to call native APIs or rely on a package that wraps these.
  //
  // For now, we'll provide a placeholder that logs a warning if the expected size
  // is very large, as a basic approximation. A proper implementation would involve
  // checking actual free disk space.

  // This is a very basic placeholder. A real implementation would check actual disk space.
  if (expectedSize > 100 * 1024 * 1024) { // Warn if file is larger than 100MB
    print(
        "Warning: Large file download detected. "
        "The expected file size is: ${(expectedSize / 1e6).toStringAsFixed(2)} MB. "
        "Please ensure enough free disk space in '$targetDir'."
    );
  }
}

/// Download a given file if it's not already present in the local cache.
///
/// The new cache file layout looks like this:
/// - The cache directory contains one subfolder per repo_id (namespaced by repo type)
/// - inside each repo folder:
///     - refs is a list of the latest known revision => commit_hash pairs
///     - blobs contains the actual file blobs (identified by their git-sha or sha256, depending on
///       whether they're LFS files or not)
///     - snapshots contains one subfolder per commit, each "commit" contains the subset of the files
///       that have been resolved at that particular commit. Each filename is a symlink to the blob
///       at that particular commit.
///
/// ```
/// [  96]  .
/// └── [ 160]  models--julien-c--EsperBERTo-small
///     ├── [ 160]  blobs
///     │   ├── [321M]  403450e234d65943a7dcf7e05a771ce3c92faa84dd07db4ac20f592037a1e4bd
///     │   ├── [ 398]  7cb18dc9bafbfcf74629a4b760af1b160957a83e
///     │   └── [1.4K]  d7edf6bd2a681fb0175f7735299831ee1b22b812
///     ├── [  96]  refs
///     │   └── [  40]  main
///     └── [ 128]  snapshots
///         ├── [ 128]  2439f60ef33a0d46d85da5001d52aeda5b00ce9f
///         │   ├── [  52]  README.md -> ../../blobs/d7edf6bd2a681fb0175f7735299831ee1b22b812
///         │   └── [  76]  pytorch_model.bin -> ../../blobs/403450e234d65943a7dcf7e05a771ce3c92faa84dd07db4ac20f592037a1e4bd
///         └── [ 128]  bbc77c8132af1cc5cf678da3f1ddf2de43606d48
///             ├── [  52]  README.md -> ../../blobs/7cb18dc9bafbfcf74629a4b760af1b160957a83e
///             └── [  76]  pytorch_model.bin -> ../../blobs/403450e234d65943a7dcf7e05a771ce3c92faa84dd07db4ac20f592037a1e4bd
/// ```
///
/// If `local_dir` is provided, the file structure from the repo will be replicated in this location. When using this
/// option, the `cache_dir` will not be used and a `.cache/huggingface/` folder will be created at the root of `local_dir`
/// to store some metadata related to the downloaded files. While this mechanism is not as robust as the main
/// cache-system, it's optimized for regularly pulling the latest version of a repository.
///
/// Args:
///     repo_id (`str`):
///         A user or an organization name and a repo name separated by a `/`.
///     filename (`str`):
///         The name of the file in the repo.
///     subfolder (`str`, *optional*):
///         An optional value corresponding to a folder inside the model repo.
///     repo_type (`str`, *optional*):
///         Set to `"dataset"` or `"space"` if downloading from a dataset or space,
///         `None` or `"model"` if downloading from a model. Default is `None`.
///     revision (`str`, *optional*):
///         An optional Git revision id which can be a branch name, a tag, or a
///         commit hash.
///     library_name (`str`, *optional*):
///         The name of the library to which the object corresponds.
///     library_version (`str`, *optional*):
///         The version of the library.
///     cache_dir (`str`, `Path`, *optional*):
///         Path to the folder where cached files are stored.
///     local_dir (`str` or `Path`, *optional*):
///         If provided, the downloaded file will be placed under this directory.
///     user_agent (`dict`, `str`, *optional*):
///         The user-agent info in the form of a dictionary or a string.
///     force_download (`bool`, *optional*, defaults to `False`):
///         Whether the file should be downloaded even if it already exists in
///         the local cache.
///     proxies (`dict`, *optional*):
///         Dictionary mapping protocol to the URL of the proxy passed to
///         `requests.request`.
///     etag_timeout (`float`, *optional*, defaults to `10`):
///         When fetching ETag, how many seconds to wait for the server to send
///         data before giving up which is passed to `requests.request`.
///     token (`str`, `bool`, *optional*):
///         A token to be used for the download.
///             - If `True`, the token is read from the HuggingFace config
///               folder.
///             - If a string, it's used as the authentication token.
///     local_files_only (`bool`, *optional*, defaults to `False`):
///         If `True`, avoid downloading the file and return the path to the
///         local cached file if it exists.
///     headers (`dict`, *optional*):
///         Additional headers to be sent with the request.
///
/// Returns:
///     `str`: Local path of file or if networking is off, last version of file cached on disk.
///
/// Raises:
///     [`~utils.RepositoryNotFoundError`]
///         If the repository to download from cannot be found. This may be because it doesn't exist,
///         or because it is set to `private` and you do not have access.
///     [`~utils.RevisionNotFoundError`]
///         If the revision to download from cannot be found.
///     [`~utils.EntryNotFoundError`]
///         If the file to download cannot be found.
///     [`~utils.LocalEntryNotFoundError`]
///         If network is disabled or unavailable and file is not found in cache.
///     [`EnvironmentError`](https://docs.python.org/3/library/exceptions.html#EnvironmentError)
///         If `token=True` but the token cannot be found.
///     [`OSError`](https://docs.python.org/3/library/exceptions.html#OSError)
///         If ETag cannot be determined.
///     [`ValueError`](https://docs.python.org/3/library/exceptions.html#ValueError)
///         If some parameter value is invalid.
Future<String> hfHubDownload({
  required String repoId,
  required String filename,
  String? subfolder,
  String? repoType,
  String? revision,
  String? libraryName,
  String? libraryVersion,
  String? cacheDir,
  String? localDir,
  dynamic userAgent,
  bool forceDownload = false,
  Map<String, String>? proxies,
  double etagTimeout = constants.DEFAULT_ETAG_TIMEOUT,
  dynamic token,
  bool localFilesOnly = false,
  Map<String, String>? headers,
  String? endpoint,
}) async {
  if (constants.HF_HUB_ETAG_TIMEOUT != constants.DEFAULT_ETAG_TIMEOUT) {
    // Respect environment variable above user value
    etagTimeout = constants.HF_HUB_ETAG_TIMEOUT.toDouble();
  }

  cacheDir ??= constants.HF_HUB_CACHE;
  revision ??= constants.DEFAULT_REVISION;

  subfolder = subfolder?.isEmpty == true ? null : subfolder;
  if (subfolder != null) {
    // This is used to create a URL, and not a local path, hence the forward slash.
    filename = '$subfolder/$filename';
  }

  repoType ??= 'model';
  if (!constants.REPO_TYPES.contains(repoType)) {
    throw ArgumentError('Invalid repo type: $repoType. Accepted repo types are: ${constants.REPO_TYPES}');
  }

  final Map<String, String> hfHeaders = await buildHfHeaders(
    token: token,
    libraryName: libraryName,
    libraryVersion: libraryVersion,
    userAgent: userAgent,
    headers: headers,
  );

  if (localDir != null) {
    return _hfHubDownloadToLocalDir(
      // Destination
      localDir: localDir,
      // File info
      repoId: repoId,
      repoType: repoType,
      filename: filename,
      revision: revision,
      // HTTP info
      endpoint: endpoint,
      etagTimeout: etagTimeout,
      headers: hfHeaders,
      proxies: proxies,
      token: token,
      // Additional options
      cacheDir: cacheDir,
      forceDownload: forceDownload,
      localFilesOnly: localFilesOnly,
    );
  }

  return await _hfHubDownloadToCacheDir(
    // Destination
    cacheDir: cacheDir,
    // File info
    repoId: repoId,
    filename: filename,
    repoType: repoType,
    revision: revision,
    // HTTP info
    endpoint: endpoint,
    etagTimeout: etagTimeout,
    headers: hfHeaders,
    proxies: proxies,
    token: token,
    // Additional options
    localFilesOnly: localFilesOnly,
    forceDownload: forceDownload,
  );
}

/// Download a given file to a cache folder, if not already present.
///
/// Method should not be called directly. Please use `hfHubDownload` instead.
Future<String> _hfHubDownloadToCacheDir({
  // Destination
  required String cacheDir,
  // File info
  required String repoId,
  required String filename,
  required String repoType,
  required String revision,
  // HTTP info
  String? endpoint,
  required double etagTimeout,
  required Map<String, String> headers,
  Map? proxies,
  dynamic token,
  // Additional options
  required bool localFilesOnly,
  required bool forceDownload,
}) async {
  final locksDir = path.join(cacheDir, '.locks');
  final storageFolder = path.join(cacheDir, repoFolderName(repoId: repoId, repoType: repoType));

  // cross platform transcription of filename, to be used as a local file path.
  final relativeFilename = path.joinAll(filename.split('/'));
  if (Platform.isWindows) {
    if (relativeFilename.startsWith('..\\') || relativeFilename.contains('\\..\\')) {
      throw ArgumentError('Invalid filename: cannot handle filename \'$relativeFilename\' on Windows. Please ask the repository owner to rename this file.');
    }
  }

  if (REGEX_COMMIT_HASH.hasMatch(revision)) {
    final pointerPath = _getPointerPath(storageFolder, revision, relativeFilename);
    if (await File(pointerPath).exists() && !forceDownload) {
      return pointerPath;
    }
  }

  // Try to get metadata (etag, commit_hash, url, size) from the server.
  // If we can't, a HEAD request error is returned.
  final (urlToDownload, etag, commitHash, expectedSize, xetFileData, headCallError) = await _getMetadataOrCatchError(
    repoId: repoId,
    filename: filename,
    repoType: repoType,
    revision: revision,
    endpoint: endpoint,
    proxies: proxies,
    etagTimeout: etagTimeout,
    headers: headers,
    token: token,
    localFilesOnly: localFilesOnly,
    storageFolder: storageFolder,
    relativeFilename: relativeFilename,
  );

  // etag can be None for several reasons:
  // 1. we passed local_files_only.
  // 2. we don't have a connection
  // 3. Hub is down (HTTP 500, 503, 504)
  // 4. repo is not found -for example private or gated- and invalid/missing token sent
  // 5. Hub is blocked by a firewall or proxy is not set correctly.
  // => Try to get the last downloaded one from the specified revision.
  //
  // If the specified revision is a commit hash, look inside "snapshots".
  // If the specified revision is a branch or tag, look inside "refs".
  if (headCallError != null) {
    // Couldn't make a HEAD call => let's try to find a local file
    if (!forceDownload) {
      String? commitHash;
      if (REGEX_COMMIT_HASH.hasMatch(revision)) {
        commitHash = revision;
      } else {
        final refPath = path.join(storageFolder, 'refs', revision);
        if (await FileSystemEntity.type(refPath) == FileSystemEntityType.file) {
          commitHash = await File(refPath).readAsString();
        }
      }

      // Return pointer file if exists
      if (commitHash != null) {
        final pointerPath = _getPointerPath(storageFolder, commitHash, relativeFilename);
        if (await File(pointerPath).exists()) {
          return pointerPath;
        }
      }
    }

    // Otherwise, raise appropriate error
    _raiseOnHeadCallError(headCallError, forceDownload, localFilesOnly);
  }

  // From now on, etag, commit_hash, url and size are not None.
  assert(etag != null, 'etag must have been retrieved from server');
  assert(commitHash != null, 'commitHash must have been retrieved from server');
  assert(urlToDownload != null, 'file location must have been retrieved from server');
  assert(expectedSize != null, 'expectedSize must have been retrieved from server');
  String blobPath = path.join(storageFolder, 'blobs', etag);
  final pointerPath = _getPointerPath(storageFolder, commitHash!, relativeFilename);

  await Directory(path.dirname(blobPath)).create(recursive: true);
  await Directory(path.dirname(pointerPath)).create(recursive: true);

  // if passed revision is not identical to commit_hash
  // then revision has to be a branch name or tag name.
  // In that case store a ref.
  await _cacheCommitHashForSpecificRevision(storageFolder, revision, commitHash);

  // Prevent parallel downloads of the same file with a lock.
  // etag could be duplicated across repos,
  String lockPath = path.join(locksDir, repoFolderName(repoId: repoId, repoType: repoType), '$etag.lock');

  // Some Windows versions do not allow for paths longer than 255 characters.
  // In this case, we must specify it as an extended path by using the "\\?\" prefix.
  if (Platform.isWindows && path.absolute(lockPath).length > 255) {
    lockPath = '\\\\?\\${path.absolute(lockPath)}';
  }

  if (Platform.isWindows && path.absolute(blobPath).length > 255) {
    blobPath = '\\\\?\\${path.absolute(blobPath)}';
  }

  await Directory(lockPath).parent.create(recursive: true);

  // pointer already exists -> immediate return
  if (!forceDownload && await File(pointerPath).exists()) {
    return pointerPath;
  }

  // Blob exists but pointer must be (safely) created -> take the lock
  if (!forceDownload && await File(blobPath).exists()) {
    return await WeakFileLock(lockPath, () async {
      if (!await File(pointerPath).exists()) {
        await _createSymlink(blobPath, pointerPath, newBlob: false);
      }
      return pointerPath;
    });
  }

  // Local file doesn't exist or etag isn't a match => retrieve file from remote (or cache)

  await WeakFileLock(lockPath, () async {
    await _downloadToTmpAndMove(
      incompletePath: "$blobPath.incomplete",
      destinationPath: blobPath,
      urlToDownload: urlToDownload!,
      proxies: proxies,
      headers: headers,
      expectedSize: expectedSize,
      filename: filename,
      forceDownload: forceDownload,
      xetFileData: xetFileData,
    );
    if (!await File(pointerPath).exists()) {
      await _createSymlink(blobPath, pointerPath, newBlob: true);
    }
  });

  return pointerPath;
}

/// Download a given file to a local folder, if not already present.
///
/// Method should not be called directly. Please use `hf_hub_download` instead.
Future<String> _hfHubDownloadToLocalDir({
  // Destination
  required String localDir,
  // File info
  required String repoId,
  required String repoType,
  required String filename,
  required String revision,
  // HTTP info
  String? endpoint,
  required double etagTimeout,
  required Map<String, String> headers,
  Map? proxies,
  dynamic token,
  // Additional options
  required String cacheDir,
  required bool forceDownload,
  required bool localFilesOnly,
}) async {
  // Some Windows versions do not allow for paths longer than 255 characters.
  // In this case, we must specify it as an extended path by using the "\\?\" prefix.
  if (Platform.isWindows && path.absolute(localDir).length > 255) {
    localDir = '\\\\?\\${path.absolute(localDir)}';
  }
  final paths = await getLocalDownloadPaths(localDir: localDir, filename: filename);
  final localMetadata = await readDownloadMetadata(localDir: localDir, filename: filename);

  // Local file exists + metadata exists + commit_hash matches => return file
  if (!forceDownload
      && REGEX_COMMIT_HASH.hasMatch(revision)
      && await FileSystemEntity.type(paths.filePath) == FileSystemEntityType.file
      && localMetadata != null
      && localMetadata.commitHash == revision
  ) {
    return paths.filePath;
  }

  // Try to get metadata (etag, commit_hash, url, size) from the server.
  // If we can't, a HEAD request error is returned.
  final (urlToDownload, etag, commitHash, expectedSize, xetFileData, headCallError) = await _getMetadataOrCatchError(
    repoId: repoId,
    filename: filename,
    repoType: repoType,
    revision: revision,
    endpoint: endpoint,
    proxies: proxies,
    etagTimeout: etagTimeout,
    headers: headers,
    token: token,
    localFilesOnly: localFilesOnly,
  );

  if (headCallError != null) {
    // No HEAD call but local file exists => default to local file
    if (!forceDownload && await FileSystemEntity.type(paths.filePath) == FileSystemEntityType.file) {
      print(
          "Couldn't access the Hub to check for update but local file already exists. "
              "Defaulting to existing file. (error: $headCallError)"
      );
      return paths.filePath;
    }

    // Otherwise => raise
    _raiseOnHeadCallError(headCallError, forceDownload, localFilesOnly);
  }

  // From now on, etag, commit_hash, url and size are not None.
  assert(etag != null, 'etag must have been retrieved from server');
  assert(commitHash != null, 'commitHash must have been retrieved from server');
  assert(urlToDownload != null, 'file location must have been retrieved from server');
  assert(expectedSize != null, 'expectedSize must have been retrieved from server');

  // Local file exists => check if it's up-to-date
  if (!forceDownload && await FileSystemEntity.type(paths.filePath) == FileSystemEntityType.file) {
    // etag matches => update metadata and return file
    if (localMetadata != null && localMetadata.etag == etag) {
      await writeDownloadMetadata(
        localDir: localDir,
        filename: filename,
        commitHash: commitHash!,
        etag: etag!,
      );
      return paths.filePath;
    }

    // metadata is outdated + etag is a sha256
    // => means it's an LFS file (large)
    // => let's compute local hash and compare
    // => if match, update metadata and return file
    if (localMetadata == null && REGEX_SHA256.hasMatch(etag!)) {
      String? fileHash;
      final stream = File(paths.filePath).openRead();

      final output = AccumulatorSink<Digest>();
      final input = sha256.startChunkedConversion(output);
      await for (final chunk in stream) {
        input.add(chunk);
      }
      input.close();
      fileHash = output.events.single.toString();

      if (fileHash == etag) {
        await writeDownloadMetadata(
          localDir: localDir,
          filename: filename,
          commitHash: commitHash!,
          etag: etag,
        );
        return paths.filePath;
      }
    }
  }

  // Local file doesn't exist or etag isn't a match => retrieve file from remote (or cache)

  // If we are lucky enough, the file is already in the cache => copy it
  if (!forceDownload) {
    final cachedPath = await tryToLoadFromCache(
      repoId: repoId,
      filename: filename,
      cacheDir: cacheDir,
      revision: revision,
      repoType: repoType,
    );
    if (cachedPath is String) {
      await WeakFileLock(paths.lockPath, () async {
        await copyFle(cachedPath, paths.filePath);
      });
      await writeDownloadMetadata(
        localDir: localDir,
        filename: filename,
        commitHash: commitHash!,
        etag: etag!,
      );
      return paths.filePath;
    }
  }

  // Otherwise, let's download the file!
  await WeakFileLock(paths.lockPath, () async {
    final f = File(paths.filePath);
    if (await f.exists()) {
      await f.delete();
    }
    await _downloadToTmpAndMove(
      incompletePath: paths.incompletePath(etag!),
      destinationPath: paths.filePath,
      urlToDownload: urlToDownload!,
      proxies: proxies,
      headers: headers,
      expectedSize: expectedSize,
      filename: filename,
      forceDownload: forceDownload,
      xetFileData: xetFileData,
    );
  });

  await writeDownloadMetadata(
    localDir: localDir,
    filename: filename,
    commitHash: commitHash!,
    etag: etag!,
  );
  return paths.filePath;
}

/// Explores the cache to return the latest cached file for a given revision if found.
///
/// This function will not raise any exception if the file in not cached.
///
/// Args:
///     cache_dir (`str` or `os.PathLike`):
///         The folder where the cached files lie.
///     repo_id (`str`):
///         The ID of the repo on huggingface.co.
///     filename (`str`):
///         The filename to look for inside `repo_id`.
///     revision (`str`, *optional*):
///         The specific model version to use. Will default to `"main"` if it's not provided and no `commit_hash` is
///         provided either.
///     repo_type (`str`, *optional*):
///         The type of the repository. Will default to `"model"`.
///
/// Returns:
///     `Optional[str]` or `_CACHED_NO_EXIST`:
///         Will return `None` if the file was not cached. Otherwise:
///         - The exact path to the cached file if it's found in the cache
///         - A special value `_CACHED_NO_EXIST` if the file does not exist at the given commit hash and this fact was
///           cached.
///
/// Example:
///
/// ```python
/// from huggingface_hub import try_to_load_from_cache, _CACHED_NO_EXIST
///
/// filepath = try_to_load_from_cache()
/// if isinstance(filepath, str):
///     # file exists and is cached
///     ...
/// elif filepath is _CACHED_NO_EXIST:
///     # non-existence of file is cached
///     ...
/// else:
///     # file is not cached
///     ...
/// ```
Future<Object?> tryToLoadFromCache({
  required String repoId,
  required String filename,
  String? cacheDir,
  String? revision,
  String? repoType,
}) async {
  revision ??= 'main';
  repoType ??= 'model';
  if (!constants.REPO_TYPES.contains(repoType)) {
    throw ArgumentError('Invalid repo type: $repoType. Accepted repo types are: ${constants.REPO_TYPES}');
  }
  cacheDir ??= constants.HF_HUB_CACHE;

  final objectId = repoId.replaceAll('/', '--');
  final repoCache = path.join(cacheDir, '${repoType}s--$objectId');
  if (await FileSystemEntity.type(repoCache) != FileSystemEntityType.directory) {
    // No cache for this model
    return null;
  }

  final refsDir = path.join(repoCache, 'refs');
  final snapshotsDir = path.join(repoCache, 'snapshots');
  final noExistDir = path.join(repoCache, '.no_exist');

  // Resolve refs (for instance to convert main to the associated commit sha)
  if (await FileSystemEntity.type(path.join(noExistDir, revision, filename)) == FileSystemEntityType.file) {
    return _CACHED_NO_EXIST;
  }

  // Check if revision folder exists
  if (!await Directory(snapshotsDir).exists()) {
    return null;
  }
  final cachedShas = await Directory(snapshotsDir).list().toList();
  if (!cachedShas.any((f) => path.basename(f.path) == revision)) {
    // No cache for this revision and we won't try to return a random revision
    return null;
  }

  // Check if file exists in cache
  final cachedFile = path.join(snapshotsDir, revision, filename);
  return await FileSystemEntity.type(cachedFile) == FileSystemEntityType.file ? cachedFile : null;
}

/// Fetch metadata of a file versioned on the Hub for a given url.
///
/// Args:
/// url (`str`):
/// File url, for example returned by [`hf_hub_url`].
/// token (`str` or `bool`, *optional*):
/// A token to be used for the download.
/// - If `True`, the token is read from the HuggingFace config
/// folder.
/// - If `False` or `None`, no token is provided.
/// - If a string, it's used as the authentication token.
/// proxies (`dict`, *optional*):
/// Dictionary mapping protocol to the URL of the proxy passed to
/// `requests.request`.
/// timeout (`float`, *optional*, defaults to 10):
/// How many seconds to wait for the server to send metadata before giving up.
/// library_name (`str`, *optional*):
/// The name of the library to which the object corresponds.
/// library_version (`str`, *optional*):
/// The version of the library.
/// user_agent (`dict`, `str`, *optional*):
/// The user-agent info in the form of a dictionary or a string.
/// headers (`dict`, *optional*):
/// Additional headers to be sent with the request.
/// endpoint (`str`, *optional*):
/// Endpoint of the Hub. Defaults to <https://huggingface.co>.
///
/// Returns:
/// A [`HfFileMetadata`] object containing metadata such as location, etag, size and
/// commit_hash.
Future<HfFileMetadata> getHfFileMetadata({
  required String url,
  dynamic token,
  Map? proxies,
  double? timeout,
  String? libraryName,
  String? libraryVersion,
  dynamic userAgent,
  Map<String, String>? headers,
  String? endpoint,
}) async {
  timeout ??= constants.DEFAULT_REQUEST_TIMEOUT;

  final hfHeaders = await buildHfHeaders(
    token: token,
    libraryName: libraryName,
    libraryVersion: libraryVersion,
    userAgent: userAgent,
    headers: headers,
  );
  hfHeaders['Accept-Encoding'] = 'identity'; // prevent any compression => we want to know the real size of the file

  // Retrieve metadata
  final r = await _requestWrapper(
    method: 'HEAD',
    url: url,
    dioOptions: Options(
      headers: hfHeaders,
      followRedirects: false,
      // proxies: proxies,
      receiveTimeout: Duration(milliseconds: (timeout * 1000).truncate()),
    ),
    followRelativeRedirects: true,
  );
  // TODO: Is this needed?
  // hfRaiseForStatus(r, raiseForStatus);

  return HfFileMetadata(
    commitHash: r.headers.value(constants.HUGGINGFACE_HEADER_X_REPO_COMMIT),
    // We favor a custom header indicating the etag of the linked resource, and
    // we fallback to the regular etag header.
    etag: _normalizeEtag(r.headers.value(constants.HUGGINGFACE_HEADER_X_LINKED_ETAG) ?? r.headers.value('ETag')),
    // Either from response headers (if redirected) or defaults to request url
    // Do not use directly `url`, as `_request_wrapper` might have followed relative
    // redirects.
    location: r.headers.value('Location') ?? r.realUri.toString(),
    size: _intOrNull(r.headers.value(constants.HUGGINGFACE_HEADER_X_LINKED_SIZE) ?? r.headers.value('Content-Length')),
    xetFileData: parseXetFileDataFromResponse(r, endpoint=endpoint),
  );
}

/// Get metadata for a file on the Hub, safely handling network issues.
///
/// Returns either the etag, commit_hash and expected size of the file, or the error
/// raised while fetching the metadata.
///
/// NOTE: This function mutates `headers` inplace! It removes the `authorization` header
/// if the file is a LFS blob and the domain of the url is different from the
/// domain of the location (typically an S3 bucket).
Future<(String?, String?, String?, int?, XetFileData?, Exception?)> _getMetadataOrCatchError({
  required String repoId,
  required String filename,
  required String repoType,
  required String revision,
  String? endpoint,
  Map? proxies,
  double? etagTimeout,
  required Map<String, String> headers,  // mutated inplace!
  dynamic token,
  required bool localFilesOnly,
  String? relativeFilename,  // only used to store `.no_exists` in cache
  String? storageFolder,  // only used to store `.no_exists` in cache
}) async {
  if (localFilesOnly) {
    return (null, null, null, null, null, OfflineModeIsEnabled(
      "Cannot access file since 'local_files_only=True' as been set. (repo_id: $repoId, repo_type: $repoType, revision: $revision, filename: $filename)",
    ));
  }

  final url = hfHubUrl(repoId, filename, repoType: repoType, revision: revision, endpoint: endpoint);
  String urlToDownload = url;
  String? etag;
  String? commitHash;
  int? expectedSize;
  Exception? headErrorCall;
  XetFileData? xetFileData;

  // Try to get metadata from the server.
  // Do not raise yet if the file is not found or not accessible.
  if (!localFilesOnly) {
    try {
      HfFileMetadata? metadata;

      try {
        metadata = await getHfFileMetadata(
          url: url,
          proxies: proxies,
          timeout: etagTimeout,
          headers: headers,
          token: token,
          endpoint: endpoint,
        );
      } on EntryNotFoundError catch (httpError) {
        if (storageFolder != null && relativeFilename != null) {
          // Cache the non-existence of the file
          final commitHash = httpError.response?.headers.value(constants.HUGGINGFACE_HEADER_X_REPO_COMMIT);
          if (commitHash != null) {
            final noExistFilePath = path.join(storageFolder, '.no_exist', commitHash, relativeFilename);
            try {
              await Directory(path.dirname(noExistFilePath)).create(recursive: true);
              await File(noExistFilePath).create();
            } on FileSystemException catch (e) {
              print('Could not cache non-existence of file. Will ignore error and continue. Error: $e');
            }
            await _cacheCommitHashForSpecificRevision(storageFolder, revision, commitHash);
          }
        }
        rethrow;
      }

      // Commit hash must exist
      commitHash = metadata.commitHash;
      if (commitHash == null) {
        throw FileMetadataError(
            'Distant resource does not seem to be on huggingface.co. It is possible that a configuration issue'
            ' prevents you from downloading resources from https://huggingface.co. Please check your firewall'
            ' and proxy settings and make sure your SSL certificates are updated.'
        );
      }

      // Etag must exist
      // If we don't have any of those, raise an error.
      etag = metadata.etag;
      if (etag == null) {
        throw FileMetadataError(
            "Distant resource does not have an ETag, we won't be able to reliably ensure reproducibility."
        );
      }

      // Size must exist
      expectedSize = metadata.size;
      if (expectedSize == null) {
        throw FileMetadataError('Distant resource does not have a Content-Length.');
      }

      xetFileData = metadata.xetFileData;

      // In case of a redirect, save an extra redirect on the request.get call,
      // and ensure we download the exact atomic version even if it changed
      // between the HEAD and the GET (unlikely, but hey).
      //
      // If url domain is different => we are downloading from a CDN => url is signed => don't send auth
      // If url domain is the same => redirect due to repo rename AND downloading a regular file => keep auth
      if (xetFileData == null && url != metadata.location) {
        urlToDownload = metadata.location;
        if (Uri.parse(url).host != Uri.parse(metadata.location).host) {
          // Remove authorization header when downloading a LFS blob
          headers.remove('authorization');
        }
      }
    } on DioException catch (e) {
      // (requests.exceptions.SSLError, requests.exceptions.ProxyError)
      if (e.type == DioExceptionType.badCertificate || e.type == DioExceptionType.unknown) {
        // Actually raise for those subclasses of ConnectionError
        rethrow;
      }

      if (e.type == DioExceptionType.connectionError
          || e.type == DioExceptionType.connectionTimeout
          || e.type == DioExceptionType.receiveTimeout
          || e.type == DioExceptionType.sendTimeout) {
        // Otherwise, our Internet connection is down.
        // etag is None
        headErrorCall = e;
      }

      // except requests.HTTPError as error:
      // Multiple reasons for an http error:
      // - Repository is private and invalid/missing token sent
      // - Repository is gated and invalid/missing token sent
      // - Hub is down (error 500 or 504)
      // => let's switch to 'local_files_only=True' to check if the files are already cached.
      //    (if it's not the case, the error will be re-raised)
      headErrorCall = e;
    } on (RevisionNotFoundError, EntryNotFoundError) catch (_) {
      // The repo was found but the revision or entry doesn't exist on the Hub (never existed or got deleted)
    }  on FileMetadataError catch (e) {
      // Multiple reasons for a FileMetadataError:
      // - Wrong network configuration (proxy, firewall, SSL certificates)
      // - Inconsistency on the Hub
      // => let's switch to 'local_files_only=True' to check if the files are already cached.
      //    (if it's not the case, the error will be re-raised)
      headErrorCall = e;
    }
  }
  
  if (!(localFilesOnly || etag != null || headErrorCall != null)) {
    throw StateError('etag is empty due to uncovered problems');
  }

  return (urlToDownload, etag, commitHash, expectedSize, xetFileData, headErrorCall);
}

void _raiseOnHeadCallError(Exception headCallError, bool forceDownload, bool localFilesOnly) {
  /// Raise an appropriate error when the HEAD call failed and we cannot locate a local file.
  // No head call => we cannot force download.
  if (forceDownload) {
    if (localFilesOnly) {
      throw ArgumentError("Cannot pass 'forceDownload=true' and 'localFilesOnly=true' at the same time.");
    } else if (headCallError is OfflineModeIsEnabled) {
      throw ArgumentError("Cannot pass 'forceDownload=true' when offline mode is enabled.");
    } else {
      throw ArgumentError("Force download failed due to the above error.");
    }
  }

  // No head call + couldn't find an appropriate file on disk => raise an error.
  if (localFilesOnly) {
    throw LocalEntryNotFoundError(
        "Cannot find the requested files in the disk cache and outgoing traffic has been disabled. To enable"
            " hf.co look-ups and downloads online, set 'localFilesOnly' to false."
    );
  } else if (headCallError is RepositoryNotFoundError || headCallError is GatedRepoError ||
      (headCallError is HfHubHTTPError && headCallError.response?.statusCode == 401)) {
    // Repo not found or gated => let's raise the actual error
    // Unauthorized => likely a token issue => let's raise the actual error
    throw headCallError;
  } else {
    // Otherwise: most likely a connection issue or Hub downtime => let's warn the user
    throw LocalEntryNotFoundError(
      "An error happened while trying to locate the file on the Hub and we cannot find the requested files"
          " in the local cache. Please check your connection and try again or make sure your Internet connection"
          " is on.",
    );
  }
}

/// Download content from a URL to a destination path.
///
/// Internal logic:
/// - return early if file is already downloaded
/// - resume download if possible (from incomplete file)
/// - do not resume download if `force_download=True` or `HF_HUB_ENABLE_HF_TRANSFER=True`
/// - check disk space before downloading
/// - download content to a temporary file
/// - set correct permissions on temporary file
/// - move the temporary file to the destination path
///
/// Both `incomplete_path` and `destination_path` must be on the same volume to avoid a local copy.
Future<void> _downloadToTmpAndMove({
  required String incompletePath,
  required String destinationPath,
  required String urlToDownload,
  Map? proxies,
  required Map<String, String> headers,
  int? expectedSize,
  required String filename,
  required bool forceDownload,
  XetFileData? xetFileData,
}) async {
  if (await File(destinationPath).exists() && !forceDownload) {
    // Do nothing if already exists (except if force_download=True)
    return;
  }

  if (await File(incompletePath).exists()
      && (forceDownload || constants.HF_HUB_ENABLE_HF_TRANSFER && proxies?.isNotEmpty == true)) {
    // By default, we will try to resume the download if possible.
    // However, if the user has set `force_download=True` or if `hf_transfer` is enabled, then we should
    // not resume the download => delete the incomplete file.
    String message = "Removing incomplete file '$incompletePath'";
    if (forceDownload) {
      message += " because 'force_download=True'";
    } else if (constants.HF_HUB_ENABLE_HF_TRANSFER && proxies?.isNotEmpty == true) {
      message += ' (hf_transfer=True)';
    }
    print(message);
    await File(incompletePath).delete();
  }

  final file = await File(incompletePath).create(recursive: true);
  RandomAccessFile f = await file.open(mode: FileMode.append);
  try {
    final resumeSize = await f.length();
    String message = "Downloading '$filename' to '$incompletePath'";
    if (resumeSize > 0 && expectedSize != null) {
      message += ' (resume from $resumeSize/$expectedSize)';
    }
    print(message);

    // might be null  if HTTP header not set correctly
    if (expectedSize != null) {
      // Check disk space in both tmp and destination path
      _checkDiskSpace(expectedSize, File(incompletePath).parent.path);
      _checkDiskSpace(expectedSize, File(destinationPath).parent.path);
    }

    if (xetFileData != null && isXetAvailable()) {
      print('Xet Storage is enabled for this repo. Downloading file from Xet Storage..');
      xetGet(
        incompletePath: incompletePath,
        xetFileData: xetFileData,
        headers: headers,
        expectedSize: expectedSize,
        displayedFilename: filename,
      );
    } else {
      if (xetFileData != null && constants.HF_HUB_DISABLE_XET) {
        print(
            "Xet Storage is enabled for this repo, but the 'hf_xet' package is not installed. "
                "Falling back to regular HTTP download. "
                "For better performance, install the package with: `pip install huggingface_hub[hf_xet]` or `pip install hf_xet`\n\n"
                "JK THIS ISN'T A PYTHON PACK LOL"
        );
      }

      await httpGet(
        urlToDownload,
        f,
        proxies: proxies,
        resumeSize: resumeSize,
        headers: headers,
        expectedSize: expectedSize,
      );
    }
  } finally {
    await f.flush();
    await f.close();
  }

  print('Download complete. Moving file to $destinationPath');
  await _chmodAndMove(incompletePath, destinationPath);
}

int? _intOrNull(String? value) => value != null ? int.tryParse(value): null;

/// Set correct permission before moving a blob from tmp directory to cache dir.
///
/// Do not take into account the `umask` from the process as there is no convenient way
/// to get it that is thread-safe.
///
/// See:
/// - About umask: https://docs.python.org/3/library/os.html#os.umask
/// - Thread-safety: https://stackoverflow.com/a/70343066
/// - About solution: https://github.com/huggingface/huggingface_hub/pull/1220#issuecomment-1326211591
/// - Fix issue: https://github.com/huggingface/huggingface_hub/issues/1141
/// - Fix issue: https://github.com/huggingface/huggingface_hub/issues/1215
Future<void> _chmodAndMove(String src, String dst) async {
  // Get umask by creating a temporary file in the cached repo folder.
  final tmpFile = File(path.join(File(dst).parent.parent.path, 'tmp_${uuid.v4()}'));
  try {
    await tmpFile.create();
    final cacheDirMode = (await tmpFile.stat()).mode;
    // TODO: Implement this
    // os.chmod(str(src), stat.S_IMODE(cache_dir_mode))
  } on FileSystemException catch (e) {
    print("Could not set the permissions on the file '$src'. Error: $e.\nContinuing without setting permissions.");
  } finally {
    try {
      await tmpFile.delete();
    } on FileSystemException catch (_) {
      // fails if `tmp_file.touch()` failed => do nothing
      // See https://github.com/huggingface/huggingface_hub/issues/2359
    }
  }

  // shutil.move(str(src), str(dst), copy_function=_copy_no_matter_what)
  moveFile(src, dst);
}

String _getPointerPath(String storageFolder, String revision, String relativeFilename) {
  // Using `os.path.abspath` instead of `Path.resolve()` to avoid resolving symlinks
  final snapshotPath = path.join(storageFolder, "snapshots");
  final pointerPath = path.join(snapshotPath, revision, relativeFilename);

  // In Dart, we don't have a direct equivalent of `os.path.abspath` or `Path.resolve()`
  // for path normalization that handles symlinks in the same way Python's `Path.resolve()` does.
  // For this specific check, we can rely on `path.isWithin` to ensure `pointerPath`
  // is indeed a subpath of `snapshotPath` after joining.
  if (!path.isWithin(snapshotPath, pointerPath)) {
    throw ArgumentError(
        'Invalid pointer path: cannot create pointer path in snapshot folder if'
            ' `storage_folder=\'$storageFolder\'`, `revision=\'$revision\'` and'
            ' `relative_filename=\'$relativeFilename\'`.'
    );
  }
  return pointerPath;
}
