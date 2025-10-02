import 'package:flutter_test/flutter_test.dart';

import 'package:huggingface_hub/huggingface_hub.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await HuggingfaceHub.ensureInitialized(throwOnFail: true);
  });

  group('hfHubDownload', () {
    group('xet', () {
      test(
        'can download to local folder google-bert/bert-base-uncased/flax_model.msgpack using xet',
            () async {
          final f = await hfHubDownload(
            repoId: 'google-bert/bert-base-uncased',
            filename: 'flax_model.msgpack',
            localDir: 'huggingface_local_test',
          );
          print('OUTPUT: $f');
          expect(f, contains('flax_model.msgpack'));
        },
      );
    });
  });
}
