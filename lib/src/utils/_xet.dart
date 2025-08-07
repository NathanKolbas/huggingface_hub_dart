import 'package:dio/dio.dart';

import 'package:huggingface_hub/src/constants.dart' as constants;
import 'package:huggingface_hub/src/utils/python_to_dart.dart';

// @dataclass(frozen=True)
class XetFileData {
  String fileHash;
  String refreshRoute;

  XetFileData({ required this.fileHash, required this.refreshRoute});
}

/// Parse XET file metadata from an HTTP response.
///
/// This function extracts XET file metadata from the HTTP headers or HTTP links
/// of a given response object. If the required metadata is not found, it returns `None`.
///
/// Args:
///     response (`requests.Response`):
///         The HTTP response object containing headers dict and links dict to extract the XET metadata from.
/// Returns:
///     `Optional[XetFileData]`:
///         An instance of `XetFileData` containing the file hash and refresh route if the metadata
///         is found. Returns `None` if the required metadata is missing.
XetFileData? parseXetFileDataFromResponse(Response? response, [String? endpoint]) {
  if (response == null) return null;

  final fileHash = response.headers.value(constants.HUGGINGFACE_HEADER_X_XET_HASH);
  if (fileHash == null) return null;

  // Manually parse the 'Link' header to replicate Python requests' `response.links`.
  final linkHeader = response.headers.value('link');
  final links = parseLinkHeader(linkHeader);

  String? refreshRoute;

  if (links.containsKey(constants.HUGGINGFACE_HEADER_LINK_XET_AUTH_KEY)) {
    refreshRoute = links[constants.HUGGINGFACE_HEADER_LINK_XET_AUTH_KEY];
  } else {
    refreshRoute = response.headers.value(constants.HUGGINGFACE_HEADER_X_XET_REFRESH_ROUTE);
  }

  if (refreshRoute == null) {
    return null;
  }

  endpoint ??= constants.ENDPOINT;
  if (refreshRoute.startsWith(constants.HUGGINGFACE_CO_URL_HOME)) {
    refreshRoute = refreshRoute.replaceAll(
      constants.HUGGINGFACE_CO_URL_HOME.replaceAll(RegExp(r'/+$'), ''), // Equal to python's `.rstrip('/')`
      endpoint.replaceAll(RegExp(r'/+$'), ''), // Equal to python's `.rstrip('/')`
    );
  }
  return XetFileData(
    fileHash: fileHash,
    refreshRoute: refreshRoute,
  );
}
