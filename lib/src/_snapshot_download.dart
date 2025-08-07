// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:huggingface_hub/src/errors.dart';
import 'package:huggingface_hub/src/file_download.dart';
import 'package:huggingface_hub/src/utils/_paths.dart';
import 'package:path/path.dart' as path;

import 'package:huggingface_hub/src/constants.dart' as constants;
import 'package:pool/pool.dart';

import 'hf_api.dart';

const int VERY_LARGE_REPO_THRESHOLD = 50_000; // After this limit, we don't consider `repo_info.siblings` to be reliable enough

/// Download repo files.
///
/// Download a whole snapshot of a repo's files at the specified revision. This is useful when you want all files from
/// a repo, because you don't know which ones you will need a priori. All files are nested inside a folder in order
/// to keep their actual filename relative to that folder. You can also filter which files to download using
/// `allow_patterns` and `ignore_patterns`.
///
/// If `local_dir` is provided, the file structure from the repo will be replicated in this location. When using this
/// option, the `cache_dir` will not be used and a `.cache/huggingface/` folder will be created at the root of `local_dir`
/// to store some metadata related to the downloaded files. While this mechanism is not as robust as the main
/// cache-system, it's optimized for regularly pulling the latest version of a repository.
///
/// An alternative would be to clone the repo but this requires git and git-lfs to be installed and properly
/// configured. It is also not possible to filter which files to download when cloning a repository using git.
///
/// Args:
///     repo_id (`str`):
///         A user or an organization name and a repo name separated by a `/`.
///     repo_type (`str`, *optional*):
///         Set to `"dataset"` or `"space"` if downloading from a dataset or space,
///         `None` or `"model"` if downloading from a model. Default is `None`.
///     revision (`str`, *optional*):
///         An optional Git revision id which can be a branch name, a tag, or a
///         commit hash.
///     cache_dir (`str`, `Path`, *optional*):
///         Path to the folder where cached files are stored.
///     local_dir (`str` or `Path`, *optional*):
///         If provided, the downloaded files will be placed under this directory.
///     library_name (`str`, *optional*):
///         The name of the library to which the object corresponds.
///     library_version (`str`, *optional*):
///         The version of the library.
///     user_agent (`str`, `dict`, *optional*):
///         The user-agent info in the form of a dictionary or a string.
///     proxies (`dict`, *optional*):
///         Dictionary mapping protocol to the URL of the proxy passed to
///         `requests.request`.
///     etag_timeout (`float`, *optional*, defaults to `10`):
///         When fetching ETag, how many seconds to wait for the server to send
///         data before giving up which is passed to `requests.request`.
///     force_download (`bool`, *optional*, defaults to `False`):
///         Whether the file should be downloaded even if it already exists in the local cache.
///     token (`str`, `bool`, *optional*):
///         A token to be used for the download.
///             - If `True`, the token is read from the HuggingFace config
///               folder.
///             - If a string, it's used as the authentication token.
///     headers (`dict`, *optional*):
///         Additional headers to include in the request. Those headers take precedence over the others.
///     local_files_only (`bool`, *optional*, defaults to `False`):
///         If `True`, avoid downloading the file and return the path to the
///         local cached file if it exists.
///     allow_patterns (`List[str]` or `str`, *optional*):
///         If provided, only files matching at least one pattern are downloaded.
///     ignore_patterns (`List[str]` or `str`, *optional*):
///         If provided, files matching any of the patterns are not downloaded.
///     max_workers (`int`, *optional*):
///         Number of concurrent threads to download files (1 thread = 1 file download).
///         Defaults to 8.
///     tqdm_class (`tqdm`, *optional*):
///         If provided, overwrites the default behavior for the progress bar. Passed
///         argument must inherit from `tqdm.auto.tqdm` or at least mimic its behavior.
///         Note that the `tqdm_class` is not passed to each individual download.
///         Defaults to the custom HF progress bar that can be disabled by setting
///         `HF_HUB_DISABLE_PROGRESS_BARS` environment variable.
///
/// Returns:
///     `str`: folder path of the repo snapshot.
///
/// Raises:
///     [`~utils.RepositoryNotFoundError`]
///         If the repository to download from cannot be found. This may be because it doesn't exist,
///         or because it is set to `private` and you do not have access.
///     [`~utils.RevisionNotFoundError`]
///         If the revision to download from cannot be found.
///     [`EnvironmentError`](https://docs.python.org/3/library/exceptions.html#EnvironmentError)
///         If `token=True` and the token cannot be found.
///     [`OSError`](https://docs.python.org/3/library/exceptions.html#OSError) if
///         ETag cannot be determined.
///     [`ValueError`](https://docs.python.org/3/library/exceptions.html#ValueError)
///         if some parameter value is invalid.
Future<String> snapshotDownload({
  required String repoId,
  String? repoType,
  String? revision,
  String? cacheDir,
  String? localDir,
  String? libraryName,
  String? libraryVersion,
  dynamic userAgent,
  Map<String, String>? proxies,
  double etagTimeout = constants.DEFAULT_ETAG_TIMEOUT,
  bool forceDownload = false,
  dynamic token,
  bool localFilesOnly = false,
  List<String>? allowPatterns,
  List<String>? ignorePatterns,
  int maxWorkers = 8,
  // tqdm_class: Optional[Type[base_tqdm]] = None,
  Map<String, String>? headers,
  String? endpoint,
}) async {
  cacheDir ??= constants.HF_HUB_CACHE;
  revision ??= constants.DEFAULT_REVISION;

  repoType ??= 'model';
  if (!constants.REPO_TYPES.contains(repoType)) {
    throw ArgumentError('Invalid repo type: $repoType. Accepted repo types are: ${constants.REPO_TYPES}');
  }

  final String storageFolder = path.join(cacheDir, repoFolderName(repoId: repoId, repoType: repoType));

  final api = HfApi(
    libraryName: libraryName,
    libraryVersion: libraryVersion,
    userAgent: userAgent,
    endpoint: endpoint,
    headers: headers,
    token: token,
  );

  RepoInfoBase? repoInfo;
  Exception? apiCallError;
  if (!localFilesOnly) {
    // try/except logic to handle different errors => taken from `hf_hub_download`
    try {
      // if we have internet connection we want to list files to download
      repoInfo = await api.repoInfo(
        repoId: repoId,
        repoType: repoType,
        revision: revision,
      );
    } on DioException catch (e) {
      // Actually raise for those subclasses of ConnectionError
      // requests.exceptions.SSLError, requests.exceptions.ProxyError
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        // Internet connection is down
        // => will try to use local files only
        apiCallError = e;
      }
    } on OfflineModeIsEnabled catch (e) {
      // Internet connection is down
      // => will try to use local files only
      apiCallError = e;
    } on RevisionNotFoundError catch (_) {
      // The repo was found but the revision doesn't exist on the Hub (never existed or got deleted)
      rethrow;
    }
  }

  // At this stage, if `repo_info` is None it means either:
  // - internet connection is down
  // - internet connection is deactivated (local_files_only=True or HF_HUB_OFFLINE=True)
  // - repo is private/gated and invalid/missing token sent
  // - Hub is down
  // => let's look if we can find the appropriate folder in the cache:
  //    - if the specified revision is a commit hash, look inside "snapshots".
  //    - f the specified revision is a branch or tag, look inside "refs".
  // => if local_dir is not None, we will return the path to the local folder if it exists.
  if (repoInfo == null) {
    // Try to get which commit hash corresponds to the specified revision
    String? commitHash;
    if (REGEX_COMMIT_HASH.hasMatch(revision)) {
      commitHash = revision;
    } else {
      final refPath = path.join(storageFolder, 'refs', revision);
      final refFile = File(refPath);
      if (await refFile.exists()) {
        // retrieve commit_hash from refs file
        commitHash = await refFile.readAsString();
      }
    }

    // Try to locate snapshot folder for this commit hash
    if (commitHash != null && localDir == null) {
      final snapshotFolder = path.join(storageFolder, 'snapshots', commitHash);
      if (await File(snapshotFolder).exists()) {
        // Snapshot folder exists => let's return it
        // (but we can't check if all the files are actually there)
        return snapshotFolder;
      }
    }

    // If local_dir is not None, return it if it exists and is not empty
    if (localDir != null) {
      localDir = localDir;
      if (await FileSystemEntity.type(localDir) == FileSystemEntityType.directory
          && !await Directory(localDir).list().isEmpty) {
        print('Returning existing local_dir `$localDir` as remote repo cannot be accessed in `snapshot_download` ($apiCallError).');
        return path.normalize(localDir);
      }
    }
    // If we couldn't find the appropriate folder on disk, raise an error.
    if (localFilesOnly) {
      throw LocalEntryNotFoundError(
          'Cannot find an appropriate cached snapshot folder for the specified revision on the local disk and '
              'outgoing traffic has been disabled. To enable repo look-ups and downloads online, pass '
              "'local_files_only=False' as input."
      );
    } else if (apiCallError is OfflineModeIsEnabled) {
      throw LocalEntryNotFoundError(
          'Cannot find an appropriate cached snapshot folder for the specified revision on the local disk and '
              'outgoing traffic has been disabled. To enable repo look-ups and downloads online, set '
              "'HF_HUB_OFFLINE=0' as environment variable."
      );
    } else if ((apiCallError is RepositoryNotFoundError || apiCallError is GatedRepoError)
        || (apiCallError is HfHubHTTPError && apiCallError.response?.statusCode == 401)) {
      // Repo not found, gated, or specific authentication error => let's raise the actual error
      throw apiCallError!;
    } else {
      // Otherwise: most likely a connection issue or Hub downtime => let's warn the user
      throw LocalEntryNotFoundError(
          'An error happened while trying to locate the files on the Hub and we cannot find the appropriate'
              ' snapshot folder for the specified revision on the local disk. Please check your internet connection'
              ' and try again.'
      );
    }
  }

  // At this stage, internet connection is up and running
  // => let's download the files!
  final String? sha = switch(repoInfo) {
    ModelInfo() => repoInfo.sha,
    DatasetInfo() => repoInfo.sha,
    SpaceInfo() => repoInfo.sha,
  };
  final List<RepoSibling>? siblings = switch(repoInfo) {
    ModelInfo() => repoInfo.siblings,
    DatasetInfo() => repoInfo.siblings,
    SpaceInfo() => repoInfo.siblings,
  };
  assert(sha != null, "Repo info returned from server must have a revision sha.");
  assert(siblings != null, "Repo info returned from server must have a siblings list.");

  // Corner case: on very large repos, the siblings list in `repo_info` might not contain all files.
  // In that case, we need to use the `list_repo_tree` method to prevent caching issues.
  List<String> repoFiles = [for (final f in siblings!) f.rfilename];
  final bool hasManFiles = siblings.length > VERY_LARGE_REPO_THRESHOLD;
  if (hasManFiles) {
    print('The repo has more than 50,000 files. Using `list_repo_tree` to ensure all files are listed.');
    repoFiles = [await for (final f in api.listRepoTree(
      repoId: repoId,
      recursive: true,
      revision: revision,
      repoType: repoType,
    )) if (f is RepoFile) f.rfilename];
  }

  Iterable<String> filteredRepoFiles = filterRepoObjects(
    items: repoFiles,
    allowPatterns: allowPatterns,
    ignorePatterns: ignorePatterns,
  );

  String tqdmDesc;
  if (!hasManFiles) {
    filteredRepoFiles = filteredRepoFiles.toList();
    tqdmDesc = 'Fetching ${filteredRepoFiles.length} files';
  } else {
    tqdmDesc = 'Fetching ... files';
  }

  final String commitHash = sha!;
  final snapshotFolder = path.join(storageFolder, 'snapshots', commitHash);
  // if passed revision is not identical to commit_hash
  // then revision has to be a branch name or tag name.
  // In that case store a ref.
  if (revision != commitHash) {
    final refPath = path.join(storageFolder, 'refs', revision);
    try {
      await Directory(path.dirname(refPath)).create(recursive: true);
      await File(refPath).writeAsString(commitHash);
    } on FileSystemException catch (e) {
      print('Ignored error while writing commit hash to $refPath: $e.');
    }
  }

  // we pass the commit_hash to hf_hub_download
  // so no network call happens if we already
  // have the file locally.
  Future<String> innerHfHubDownload(String repoFile) async => await hfHubDownload(
    repoId: repoId,
    filename: repoFile,
    repoType: repoType,
    revision: commitHash,
    endpoint: endpoint,
    cacheDir: cacheDir,
    localDir: localDir,
    libraryName: libraryName,
    libraryVersion: libraryVersion,
    userAgent: userAgent,
    proxies: proxies,
    etagTimeout: etagTimeout,
    forceDownload: forceDownload,
    token: token,
    headers: headers,
  );

  if (constants.HF_HUB_ENABLE_HF_TRANSFER) {
    // when using hf_transfer we don't want extra parallelism
    // from the one hf_transfer provides
    for (final file in filteredRepoFiles) {
      innerHfHubDownload(file);
    }
  } else {
    // This block is the Dart equivalent of the Python `thread_map`.

    // 1. Create a Pool to limit concurrency to `maxWorkers`.
    final pool = Pool(maxWorkers);

    // 2. Map each file to a Future that will be executed by the pool.
    final List<Future<String>> downloadFutures = filteredRepoFiles.map((repoFile) {
      // pool.withResource() "acquires" a worker from the pool.
      // It runs the async function and releases the worker when the Future completes.
      return pool.withResource(() => innerHfHubDownload(repoFile));
    }).toList();

    // 3. Wait for all the download futures to complete.
    try {
      await Future.wait(downloadFutures);
    } finally {
      // 5. Ensure the pool and progress bar are closed.
      await pool.close();
    }
  }

  if (localDir != null) {
    return await Directory(localDir).resolveSymbolicLinks();
  }

  return snapshotFolder;
}
