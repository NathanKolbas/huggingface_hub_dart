import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:huggingface_hub/huggingface_hub.dart' as huggingface_hub;
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

String formatBytes(int bytes, [int decimals = 2]) {
  if (bytes == 0) return "0 B";
  if (bytes < 0) return "Unknown";

  const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB"];
  final i = (log(bytes) / log(1024)).floor();
  final size = bytes / pow(1024, i);
  String result = size.toStringAsFixed(decimals);
  result = result.replaceAll(RegExp(r"\.?0+$"), "");
  return "$result ${suffixes[i]}";
}

String _monthName(int month) {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ];
  return months[month - 1];
}

String formatLastModified(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return "Just now";
  } else if (difference.inMinutes < 60) {
    return "${difference.inMinutes} min${difference.inMinutes > 1 ? 's' : ''} ago";
  } else if (difference.inHours < 24) {
    return "${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago";
  } else if (difference.inDays == 1) {
    return "Yesterday";
  } else if (difference.inDays < 7) {
    return "${difference.inDays} days ago";
  } else {
    // For dates older than a week, show a formatted date
    return "${dateTime.day.toString().padLeft(2, '0')} "
        "${_monthName(dateTime.month)} ${dateTime.year}";
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await huggingface_hub.HuggingfaceHub.ensureInitialized(throwOnFail: true);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (context) => DirectoryViewerProvider()),
    ],
    child: const MyApp(),
  ));
}

class DirectoryViewerProvider extends ChangeNotifier {
  static final cacheDir = Directory(huggingface_hub.HF_HUB_CACHE);

  DirectoryViewerProvider() {
    _listenForFileChanges();
  }

  Directory _rootDir = cacheDir;

  Directory get rootDir => _rootDir;

  set rootDir(Directory value) {
    _rootDir = value;
    currentDir = value;
    notifyListeners();
  }

  Directory _currentDir = cacheDir;

  Directory get currentDir => _currentDir;

  set currentDir(Directory value) {
    _currentDir = value;
    _listenForFileChanges();
    notifyListeners();
  }

  List<(FileStat, FileSystemEntity)>? _files;

  List<(FileStat, FileSystemEntity)>? get files => _files;

  StreamSubscription<FileSystemEvent>? fileStream;

  void Function()? cancelWaitingForDir;

  /// Gives values so that sort puts directories at the top and everything else
  /// below
  int getFileSystemEntityTypeSortValue(FileSystemEntityType type) => switch (type) {
    FileSystemEntityType.directory => 0,
    FileSystemEntityType.file => 1,
    FileSystemEntityType.link => 1,
    FileSystemEntityType.notFound => 0,
    FileSystemEntityType.pipe => 1,
    FileSystemEntityType.unixDomainSock => 1,
    FileSystemEntityType() => -1,
  };

  void onFilesChanged([FileSystemEvent? event]) async {
    if (!await currentDir.exists()) {
      await _listenForFileChanges();
      return;
    }

    _files = await Future.wait((await currentDir.list().toList()).map((e) async => (await e.stat(), e)));
    _files?.sort((a, b) {
      final aValue = getFileSystemEntityTypeSortValue(a.$1.type);
      final bValue = getFileSystemEntityTypeSortValue(b.$1.type);
      return aValue.compareTo(bValue);
    });

    notifyListeners();
  }

  /// Waits until the directory at [path] exists.
  Future<void Function()> waitForDirectory(
      {
        required Directory dir,
        required void Function() onDirectoryExists,
        Duration checkInterval = const Duration(seconds: 1),
      }) async {
    Timer? timer;

    void check() {
      if (dir.existsSync()) {
        timer?.cancel();
        onDirectoryExists();
      }
    }

    timer = Timer.periodic(checkInterval, (_) => check());
    check();

    return () => timer?.cancel();
  }

  Future<void> _listenForFileChanges() async {
    await _cancelListeners();

    cancelWaitingForDir = await waitForDirectory(
      dir: currentDir,
      onDirectoryExists: () {
        try {
          fileStream = currentDir.watch().listen(onFilesChanged);
        } on FileSystemException catch (e) {
          if (!e.message.contains('File system watching is not supported')) {
            rethrow;
          }

          // The system doesn't support watch so periodically refresh
          fileStream = Stream.periodic(const Duration(seconds: 1), (_) {
            return FileSystemCreateEvent('', false);
          }).listen(onFilesChanged);
        }
        onFilesChanged();
      }
    );

    notifyListeners();
  }

  Future<void> _cancelListeners() async {
    _files = null;
    await fileStream?.cancel();
    fileStream = null;
    cancelWaitingForDir?.call();
    cancelWaitingForDir = null;
  }

  bool canGoUpDir() => _rootDir.path != _currentDir.path;

  Future<void> goUpDir() async {
    if (!canGoUpDir()) return;

    currentDir = currentDir.parent;
    notifyListeners();

    await _listenForFileChanges();
  }

  Future<void> goToDir(Directory dir) async {
    currentDir = dir;
    notifyListeners();

    await _listenForFileChanges();
  }

  String currentPathDisplay() {
    final relativePath = path.relative(_currentDir.path, from: _rootDir.path);

    if (relativePath == '.') {
      return '';
    }

    return relativePath;
  }

  @override
  void dispose() async {
    await _cancelListeners();
    super.dispose();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final TextEditingController repoIdTextEditingController = TextEditingController(
    text: 'google-bert/bert-base-uncased/README.md',
  );

  Future<void> downloadRepo() async {
    String repoId = repoIdTextEditingController.text;
    String? filePath;
    if (repoId.isEmpty) return;

    final split = repoId.split('/');
    if (split.length > 2) {
      repoId = split.sublist(0, 2).join('/');
      filePath = split.sublist(2).join('/');
    }

    if (filePath == null) {
      final output = await huggingface_hub.snapshotDownload(
        repoId: repoId,
      );
      print('Downloaded to "$output"');
    } else {
      final output = await huggingface_hub.hfHubDownload(
        repoId: repoId,
        filename: filePath,
      );
      print('Downloaded to "$output"');
    }
  }

  @override
  void dispose() async {
    repoIdTextEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Huggingface Hub'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                spacing: 8,
                children: [
                  Text(
                    'The repo id to download from e.g. '
                        '"google-bert/bert-base-uncased" or a file in the repo '
                        'formated as "REPO_ID/FILE_PATH" e.g. '
                        'google-bert/bert-base-uncased/README.md',
                  ),
                  TextField(
                    controller: repoIdTextEditingController,
                    decoration: InputDecoration(
                      labelText: 'Repo ID/File Path',
                      hintText: 'google-bert/bert-base-uncased',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: OutlinedButton(
                onPressed: downloadRepo,
                child: const Text('Download repo'),
              ),
            ),
            Expanded(
              child: DirectoryNavigator(),
            ),
          ],
        ),
      ),
    );
  }
}

class DirectoryNavigator extends StatefulWidget {
  const DirectoryNavigator({super.key});

  @override
  State<DirectoryNavigator> createState() => _DirectoryNavigatorState();
}

class _DirectoryNavigatorState extends State<DirectoryNavigator> {
  (FileStat, FileSystemEntity)? openedItem;

  void onPackPressed() async {
    if (openedItem != null) {
      openedItem = null;
    } else {
      await context.read<DirectoryViewerProvider>().goUpDir();
    }

    setState(() {});
  }

  void onItemPressed((FileStat, FileSystemEntity) pressedFileInfo) async {
    final (fileType, file) = pressedFileInfo;
    if (fileType.type == FileSystemEntityType.directory) {
      await context.read<DirectoryViewerProvider>().goToDir(Directory(file.path));
    } else {
      openedItem = pressedFileInfo;
    }

    setState(() {});
  }

  String formatFileSubtext(FileStat fileStat) {
    final dateModified = 'Date modified: ${formatLastModified(fileStat.modified)}';

    if (fileStat.type == FileSystemEntityType.directory) {
      return dateModified;
    }

    return '$dateModified\nSize: ${formatBytes(fileStat.size)}';
  }

  Future<void> deleteFile(FileSystemEntity file) async {
    await file.delete(recursive: true);
    openedItem = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final files = context.select<DirectoryViewerProvider, List<(FileStat, FileSystemEntity)>?>((p) => p.files);
    final currentDir = context.select<DirectoryViewerProvider, Directory>((p) => p.currentDir);

    return Scaffold(
      appBar: AppBar(
        leading: context.select<DirectoryViewerProvider, bool>((p) => p.canGoUpDir()) || openedItem != null ? IconButton(
          onPressed: onPackPressed,
          icon: const Icon(Icons.arrow_back),
        ) : null,
        title: Text(
          context.select<DirectoryViewerProvider, String>((p) => p.currentPathDisplay()),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      body: Builder(
        builder: (context) {
          if (files == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 4,
                children: [
                  const CircularProgressIndicator(),
                  const Text('Loading files...'),
                ],
              ),
            );
          }

          if (openedItem != null) {
            final (fileType, file) = openedItem!;

            return fileType.type == FileSystemEntityType.file ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                const Icon(
                  Icons.description,
                  size: 84,
                ),
                Text(
                  '${path.basename(file.path)}\n${formatFileSubtext(fileType)}',
                  textAlign: TextAlign.center,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => deleteFile(file),
                      icon: const Icon(Icons.delete_forever),
                    ),
                  ],
                ),
              ],
            ) : const SizedBox.shrink();
          }

          return ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, i) {
              final (fileStat, file) = files[i];

              return ListTile(
                onTap: () => onItemPressed((fileStat, file)),
                leading: fileStat.type == FileSystemEntityType.directory
                    ? const Icon(Icons.folder)
                    : const Icon(Icons.description),
                title: Text(
                  path.relative(file.path, from: currentDir.path),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(formatFileSubtext(fileStat)),
                trailing: IconButton.filledTonal(
                  onPressed: () => deleteFile(file),
                  icon: const Icon(Icons.delete_forever),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
