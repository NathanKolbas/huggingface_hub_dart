// Contains utilities to handle pagination on Huggingface Hub.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:huggingface_hub/src/_http.dart';
import 'package:huggingface_hub/src/utils/python_to_dart.dart';

/// Fetch a list of models/datasets/spaces and paginate through results.
///
/// This is using the same "Link" header format as GitHub.
/// See:
/// - https://requests.readthedocs.io/en/latest/api/#requests.Response.links
/// - https://docs.github.com/en/rest/guides/traversing-with-pagination#link-header
Stream<Map<String, dynamic>> paginate({
  required String path,
  required Map<String, dynamic> params,
  required Map<String, dynamic> headers,
}) async* {
  final session = getSession();
  final (r, raiseForStatus) = await raiseForStatusDioWrapper(() async {
    return await session.get(
      path,
      queryParameters: params,
      options: Options(
        responseType: ResponseType.json,
        headers: headers,
      ),
    );
  });
  hfRaiseForStatus(r, raiseForStatus);
  yield r.data;

  // Follow pages
  // Next link already contains query params
  String? nextPage = _getNextPage(r);
  while (nextPage != null) {
    print('Pagination detected. Requesting next page: $nextPage');
    final (r, raiseForStatus) = await httpBackoff(
      method: 'GET',
      url: nextPage,
      maxRetries: 20,
      retryOnStatusCodes: [429],
      dioOptions: Options(headers: headers),
    );
    hfRaiseForStatus(r, raiseForStatus);
    yield r.data;
    nextPage = _getNextPage(r);
  }
}

String? _getNextPage(Response r) {
  // response.links.get("next", {}).get("url")
  // TODO: Need to check if this code is correct
  final linkHeader = r.headers.value('link');
  final next = parseLinkHeader(linkHeader)['next'];
  return (next != null ? jsonDecode(next) : {})['url'];
}
