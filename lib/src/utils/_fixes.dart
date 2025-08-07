import 'dart:io' show RandomAccessFile, File, Directory;
import 'dart:math';

import 'package:path/path.dart' as path;

/// Generates a random string of a given [length] from a set of [characters].
String generateRandomString([int length = 8, String characters = 'abcdefghijklmnopqrstuvwxyz0123456789_']) {
  final random = Random();
  return List.generate(length, (_) {
    final randomIndex = random.nextInt(characters.length);
    return characters[randomIndex];
  }).join('');
}

/// Create a temporary directory and safely delete it
Future<T> SoftTemporaryDirectory<T>(String dir, Future<T> Function(Directory) fn) async {
  final tempName = generateRandomString();
  final tempDirPath = path.join(dir, tempName);
  final tempDir = await Directory(tempDirPath).create(recursive: true);
  try {
    return await fn(tempDir);
  } finally {
    await tempDir.delete(recursive: true);
  }
}

/// Create a weak file lock for the given file
Future<T> WeakFileLock<T>(String path, Future<T> Function() underLock) async {
  final f = File(path);
  if (!await f.exists()) {
    await f.create(recursive: true);
  }
  final RandomAccessFile raf = await f.open();
  try {
    await raf.lock();
    return await underLock();
  } finally {
    await raf.close();
    await f.delete();
  }
}
