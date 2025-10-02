
# Huggingface Hub Dart

🚧 **THIS IS CURRENTLY A WORK IN PROGRESS** 🚧

The unofficial Dart client for the Huggingface Hub.

Not all of the methods/functions have been implemented yet from the official huggingface_hub. However, the commonly used ones to download models/files, repos, etc. are implemented.

Flutter is required at the time of writing. This is due to the [path_provider package](https://pub.dev/packages/path_provider). If someone has a nice way to disable the path_provider package unless running on mobile/flutter then this would be amazing and pure dart will work!

For web support, the plan would be to do something similar to [transformers.js](https://github.com/huggingface/transformers.js) by either calling it directly or writing it in dart. This is not yet implemented which means web is not currently supported.

## Setup

To make sure everything is set up call `HuggingfaceHub.ensureInitialized` from the initialization of your application. Here is an example for a flutter application:

```dart
import 'package:flutter/widgets.dart';
import 'package:huggingface_hub/huggingface_hub.dart';

void main() async {  
  WidgetsFlutterBinding.ensureInitialized();
  await HuggingfaceHub.ensureInitialized();
  
  // Rest of your main function...
}
```

### MacOS

You may need the internet permission so that models can be downloaded. To do this add the following to both your `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

If you are looking for a concrete example checkout the `example/` directory.

TODO: This might be possible to put directly in the package so others don't have to do this

### iOS

You may need the internet permission so that models can be downloaded. To do this add the following to your `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
   <key>NSAllowsArbitraryLoads</key><true/>
</dict>
```

I did not have to do this but just in case you run into this issue you'll know how to fix it.

TODO: This might be possible to put directly in the package so others don't have to do this

## Example

The example for this library contains a way to see how downloading works. May be helpful to get you started!

You can either copy the code or just try running the flutter application to see how things work. Please don't be too critical of the code - I hastily put together an example.

## Version

This library is based off of commit [9e0493cfdb4de5a27b45c53c3342c83ab1a138fb](https://github.com/huggingface/huggingface_hub/tree/9e0493cfdb4de5a27b45c53c3342c83ab1a138fb) from the official [Huggingface Hub](https://github.com/huggingface/huggingface_hub) library.

## Supported Devices

There is no Web support at the moment do to no file storage.

### Windows

✔️ Tested and works.

### MacOS

✔️ Tested and works.

### Linux

✔️ Tested and works.

### Android

✔️ Tested and works.

### iOS

✔️ Tested and works.

### Web

❌ Not implemented/supported.

## Tests

There are a lot of tests that _should_ be added (hopefully one day...). Here is the structure:

- `test` tests contained in the folder should only use dart. If you try to use flutter required capabilities use below.
- `example/integration_test` for use with flutter/native/rust libraries. This will change once [the official toolchain](https://github.com/dart-lang/native/issues/883) for dart is released. You can find more information noted in [flutter_rust_bridge's documentation](https://cjycode.com/flutter_rust_bridge/guides/miscellaneous/pure-dart).
  - Tests that need to use `hf_xet`, rust, etc. should be put here
