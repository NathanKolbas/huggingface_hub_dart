# Huggingface Hub Dart

The unofficial Dart client for the Huggingface Hub.

Not all of the methods/functions have been implemented yet from the official huggingface_hub. However, the commonly used ones to download models/files, repos, etc. are implemented.

Xet is not yet implemented but is in the works.

At of the time of writing, this is a pure dart package, however, to support other platforms (such as mobile) this may change to a flutter plugin.

For web support, the plan would be to do something similar to [transformers.js](https://github.com/huggingface/transformers.js) by either calling it directly or writing it in dart. This is not yet implemented which means web is not currently supported.

## Version

This library is based off of commit [9e0493cfdb4de5a27b45c53c3342c83ab1a138fb](https://github.com/huggingface/huggingface_hub/tree/9e0493cfdb4de5a27b45c53c3342c83ab1a138fb) from the official [Huggingface Hub](https://github.com/huggingface/huggingface_hub) library.

## Supported Devices

In theory, this library should work across all platforms except for the Web do to no file storage. Please see each section to know which platform has been tested.

### Windows

✔️ Tested and works.

### MacOS

❓ Not tested yet.

### Linux

❓ Not tested yet.

### Android

❓ Not tested yet.

### iOS

❓ Not tested yet.

### Web

❌ Not yet implemented.
