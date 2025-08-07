import 'package:flutter_test/flutter_test.dart';

import 'package:huggingface_hub/huggingface_hub.dart';

void main() {
  group('_snapshot_download', () {
    group('snapshotDownload', () {
      test('can download huggingface/test-model-repo', () async {
        final f = await snapshotDownload(repoId: 'huggingface/test-model-repo');
        print('OUTPUT: $f');
        expect(f, contains('models--huggingface--test-model-repo'));
      });

      test('can download to local folder huggingface/test-model-repo', () async {
        final f = await snapshotDownload(
          repoId: 'huggingface/test-model-repo',
          localDir: 'huggingface_local_test',
        );
        print('OUTPUT: $f');
        expect(f, contains('huggingface_local_test'));
      });
    });
  });

  group('hfHubDownload', () {
    test('can download google-bert/bert-base-uncased', () async {
      final f = await hfHubDownload(repoId: 'google-bert/bert-base-uncased', filename: 'README.md');
      print('OUTPUT: $f');
      expect(f, contains('README.md'));
    });

    test('can download to local folder google-bert/bert-base-uncased', () async {
      final f = await hfHubDownload(
        repoId: 'google-bert/bert-base-uncased',
        filename: 'README.md',
        localDir: 'huggingface_local_test',
      );
      print('OUTPUT: $f');
      expect(f, contains('README.md'));
    });
  });
}
