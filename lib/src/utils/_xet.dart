import 'package:dio/dio.dart';
import 'package:huggingface_hub/src/_http.dart';

import 'package:huggingface_hub/src/constants.dart' as constants;
import 'package:huggingface_hub/src/utils/python_to_dart.dart';

// @dataclass(frozen=True)
class XetFileData {
  String fileHash;
  String? refreshRoute;

  XetFileData({ required this.fileHash, this.refreshRoute});
}

// @dataclass(frozen=True)
class XetConnectionInfo {
  String accessToken;
  int expirationUnixEpoch;
  String endpoint;

  XetConnectionInfo({
    required this.accessToken,
    required this.expirationUnixEpoch,
    required this.endpoint,
  });
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

/// Parse XET connection info from the HTTP headers or return None if not found.
/// Args:
///     headers (`Dict`):
///        HTTP headers to extract the XET metadata from.
/// Returns:
///     `XetConnectionInfo` or `None`:
///         The information needed to connect to the XET storage service.
///         Returns `None` if the headers do not contain the XET connection info.
XetConnectionInfo? parseXetConnectionInfoFromHeaders(Headers headers) {
  try {
    final endpoint = headers.value(constants.HUGGINGFACE_HEADER_X_XET_ENDPOINT);
    final accessToken = headers.value(constants.HUGGINGFACE_HEADER_X_XET_ACCESS_TOKEN);
    final expirationUnixEpoch = int.tryParse(headers.value(constants.HUGGINGFACE_HEADER_X_XET_EXPIRATION) ?? 'x');

    if (endpoint == null || accessToken == null || expirationUnixEpoch == null) {
      return null;
    }

    return XetConnectionInfo(
      accessToken: accessToken,
      expirationUnixEpoch: expirationUnixEpoch,
      endpoint: endpoint,
    );
  } catch (_) {
    return null;
  }
}

/// Utilizes the information in the parsed metadata to request the Hub xet connection information.
/// This includes the access token, expiration, and XET service URL.
/// Args:
///     file_data: (`XetFileData`):
///         The file data needed to refresh the xet connection information.
///     headers (`Dict[str, str]`):
///         Headers to use for the request, including authorization headers and user agent.
/// Returns:
///     `XetConnectionInfo`:
///         The connection information needed to make the request to the xet storage service.
/// Raises:
///     [`~utils.HfHubHTTPError`]
///         If the Hub API returned an error.
///     [`ValueError`](https://docs.python.org/3/library/exceptions.html#ValueError)
///         If the Hub API response is improperly formatted.
Future<XetConnectionInfo> refreshXetConnectionInfo({
  required XetFileData fileData,
  required Map<String, String> headers,
}) async {
  final refreshRoute = fileData.refreshRoute;
  if (refreshRoute == null) {
    throw ArgumentError("The provided xet metadata does not contain a refresh endpoint.");
  }

  return await _fetchXetConnectionInfoWithUrl(refreshRoute, headers);
}

/// Requests the xet connection info from the supplied URL. This includes the
/// access token, expiration time, and endpoint to use for the xet storage service.
/// Args:
///     url: (`str`):
///         The access token endpoint URL.
///     headers (`Dict[str, str]`):
///         Headers to use for the request, including authorization headers and user agent.
///     params (`Dict[str, str]`, `optional`):
///         Additional parameters to pass with the request.
/// Returns:
///     `XetConnectionInfo`:
///         The connection information needed to make the request to the xet storage service.
/// Raises:
///     [`~utils.HfHubHTTPError`]
///         If the Hub API returned an error.
///     [`ValueError`](https://docs.python.org/3/library/exceptions.html#ValueError)
///         If the Hub API response is improperly formatted.
Future<XetConnectionInfo> _fetchXetConnectionInfoWithUrl(
  String url,
  Map<String, String> headers,
  [Map<String, String>? params]
) async {
  final (r, raiseForStatus) = await raiseForStatusDioWrapper(() async {
    return await getSession().get(
      url,
      queryParameters: params,
      options: Options(
        responseType: ResponseType.json,
        headers: headers,
      ),
    );
  });
  hfRaiseForStatus(r, raiseForStatus);

  final metadata = parseXetConnectionInfoFromHeaders(r.headers);
  if (metadata == null) {
    throw ArgumentError("Xet headers have not been correctly set by the server.");
  }

  return metadata;
}
