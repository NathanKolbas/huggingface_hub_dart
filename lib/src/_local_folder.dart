import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:huggingface_hub/src/utils/_fixes.dart';
import 'package:huggingface_hub/src/utils/python_to_dart.dart';
import 'package:path/path.dart' as path;

/// Paths to the files related to a download process in a local dir.
///
/// Returned by [`get_local_download_paths`].
///
/// Attributes:
/// file_path (`Path`):
/// Path where the file will be saved.
/// lock_path (`Path`):
/// Path to the lock file used to ensure atomicity when reading/writing metadata.
/// metadata_path (`Path`):
/// Path to the metadata file.
// @dataclass
class LocalDownloadFilePaths {
  String filePath;

  String lockPath;

  String metadataPath;

  LocalDownloadFilePaths({
    required this.filePath,
    required this.lockPath,
    required this.metadataPath,
  });

  /// Return the path where a file will be temporarily downloaded before being moved to `file_path`.
  String incompletePath(String etag) {
    return path.join(File(metadataPath).parent.path, "${_shortHash(path.basename(metadataPath))}.$etag.incomplete");
  }
}

/// Metadata about a file in the local directory related to a download process.
///
/// Attributes:
///     filename (`str`):
///         Path of the file in the repo.
///     commit_hash (`str`):
///         Commit hash of the file in the repo.
///     etag (`str`):
///         ETag of the file in the repo. Used to check if the file has changed.
///         For LFS files, this is the sha256 of the file. For regular files, it corresponds to the git hash.
///     timestamp (`int`):
///         Unix timestamp of when the metadata was saved i.e. when the metadata was accurate.
// @dataclass
class LocalDownloadFileMetadata {
  String filename;

  String commitHash;

  String etag;

  /// Unix timestamp of when the metadata was saved i.e. when the metadata was accurate.
  ///
  /// E.g. the timestamp looks like "1753339377.418567" which is equivalent to the dart code:
  /// DateTime.now().microsecondsSinceEpoch / 1_000_000;
  /// or on web (due to 53 bit double precision):
  /// DateTime.now().millisecondsSinceEpoch / 1_000;
  double timestamp;

  LocalDownloadFileMetadata({
    required this.filename,
    required this.commitHash,
    required this.etag,
    required this.timestamp,
  });
}

/// Compute paths to the files related to a download process.
///
/// Folders containing the paths are all guaranteed to exist.
///
/// Args:
///     local_dir (`Path`):
///         Path to the local directory in which files are downloaded.
///     filename (`str`):
///         Path of the file in the repo.
///
/// Return:
///     [`LocalDownloadFilePaths`]: the paths to the files (file_path, lock_path, metadata_path, incomplete_path).
Future<LocalDownloadFilePaths> getLocalDownloadPaths({
  required String localDir,
  required String filename,
}) async {
  // filename is the path in the Hub repository (separated by '/')
  // make sure to have a cross platform transcription
  final sanitizedFilename = path.joinAll(filename.split('/'));
  if (Platform.isWindows) {
    if (sanitizedFilename.startsWith('..\\') || sanitizedFilename.contains('\\..\\')) {
      throw ArgumentError(
          "Invalid filename: cannot handle filename '$sanitizedFilename' on Windows. Please ask the repository"
          ' owner to rename this file.'
      );
    }
  }
  String filePath = path.join(localDir, sanitizedFilename);
  String metadataPath = path.join(await _huggingfaceDir(localDir), 'download', '$sanitizedFilename.metadata');
  String lockPath = path.setExtension(metadataPath, '.lock');

  // Some Windows versions do not allow for paths longer than 255 characters.
  // In this case, we must specify it as an extended path by using the "\\?\" prefix
  if (Platform.isWindows) {
    if (!localDir.startsWith('\\\\?\\') && path.absolute(lockPath).length > 255) {
      filePath = '\\\\?\\${path.absolute(filePath)}';
      metadataPath = '\\\\?\\${path.absolute(metadataPath)}';
      lockPath = '\\\\?\\${path.absolute(lockPath)}';
    }
  }

  await File(filePath).parent.create(recursive: true);
  await File(metadataPath).parent.create(recursive: true);
  return LocalDownloadFilePaths(filePath: filePath, lockPath: lockPath, metadataPath: metadataPath);
}

/// Read metadata about a file in the local directory related to a download process.
///
/// Args:
///     local_dir (`Path`):
///         Path to the local directory in which files are downloaded.
///     filename (`str`):
///         Path of the file in the repo.
///
/// Return:
///     `[LocalDownloadFileMetadata]` or `None`: the metadata if it exists, `None` otherwise.
Future<LocalDownloadFileMetadata?> readDownloadMetadata({
  required String localDir,
  required String filename,
}) async {
  final paths = await getLocalDownloadPaths(localDir: localDir, filename: filename);

  return await WeakFileLock(paths.lockPath, () async {
    if (await File(paths.metadataPath).exists()) {
      LocalDownloadFileMetadata? metadata;

      try {
        final lines = await File(paths.metadataPath)
            .openRead()
            .transform(utf8.decoder)
            .transform(LineSplitter())
            .toList();
        final commitHash = lines.removeAt(0).trim();
        final etag = lines.removeAt(0).trim();
        final timestamp = double.parse(lines.removeAt(0).trim());
        metadata = LocalDownloadFileMetadata(
          filename: filename,
          commitHash: commitHash,
          etag: etag,
          timestamp: timestamp,
        );
      } catch (e) {
        // remove the metadata file if it is corrupted / not the right format
        print('Invalid metadata file ${paths.metadataPath}: $e. Removing it from disk and continue.');
        try {
          await File(paths.metadataPath).delete();
        } catch (e) {
          print('Could not remove corrupted metadata file ${paths.metadataPath}: $e');
        }
      }

      // check if the file exists and hasn't been modified since the metadata was saved
      final stat = await File(paths.filePath).stat();

      // file does not exist => metadata is outdated
      if (stat.type == FileSystemEntityType.notFound) return null;
      // allow 1s difference as stat.st_mtime might not be precise
      if (metadata != null && (unixTimestamp(stat.modified) - 1) <= metadata.timestamp) {
        return metadata;
      }
    }

    return null;
  });
}

/// Write metadata about a file in the local directory related to a download process.
///
/// Args:
///     local_dir (`Path`):
///         Path to the local directory in which files are downloaded.
Future<void> writeDownloadMetadata({
  required String localDir,
  required String filename,
  required String commitHash,
  required String etag,
}) async {
  final paths = await getLocalDownloadPaths(localDir: localDir, filename: filename);
  await WeakFileLock(paths.lockPath, () async {
    await File(paths.metadataPath).writeAsString('$commitHash\n$etag\n${unixTimestamp()}\n');
  });
}

/// Return the path to the `.cache/huggingface` directory in a local directory.
Future<String> _huggingfaceDir(String localDir) async {
  // Wrap in lru_cache to avoid overwriting the .gitignore file if called multiple times
  final pathStr = path.join(localDir, '.cache', 'huggingface');
  await Directory(pathStr).create(recursive: true);

  // Create a .gitignore file in the .cache/huggingface directory if it doesn't exist
  // Should be thread-safe enough like this.
  final gitignore = path.join(pathStr, '.gitignore');
  final gitignoreLock = path.join(pathStr, '.gitignore.lock');
  if (!await File(gitignore).exists()) {
    await WeakFileLock(gitignoreLock, () async {
      await File(gitignore).writeAsString('*');
    });

    try {
      await File(gitignoreLock).delete();
    } on FileSystemException catch (_) {
      // Ignored
    }
  }
  return pathStr;
}

String _shortHash(String filename) {
  return base64Url.encode(sha1.convert(filename.codeUnits).bytes);
}
