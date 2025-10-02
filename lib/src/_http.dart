// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:convert';
import 'dart:io' show File;
import 'dart:math';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:huggingface_hub/src/errors.dart';

// Both headers are used by the Hub to debug failed requests.
// `X_AMZN_TRACE_ID` is better as it also works to debug on Cloudfront and ALB.
// If `X_AMZN_TRACE_ID` is set, the Hub will use it as well.
final String X_AMZN_TRACE_ID = 'X-Amzn-Trace-Id';
final String X_REQUEST_ID = 'x-request-id';

// The original python regex:
// r"""
// # staging or production endpoint
// ^https://[^/]+
// (
//     # on /api/repo_type/repo_id
//     /api/(models|datasets|spaces)/(.+)
//     |
//     # or /repo_id/resolve/revision/...
//     /(.+)/resolve/(.+)
// )
// """
final RegExp REPO_API_REGEX = RegExp(
  r"^https://[^/]+(/api/(models|datasets|spaces)/(.+)|/(.+)/resolve/(.+))",
);

Dio _setupSession() {
  final dio = Dio();
  final cookieJar = CookieJar();
  dio.interceptors.add(CookieManager(cookieJar));
  return dio;
}

// TODO: This is temp until more is implemented. Need to implement OfflineAdapter and UniqueRequestIdAdapter
Dio dio = _setupSession();

/// Get a `requests.Session` object, using the session factory from the user.
///
/// Use [`get_session`] to get a configured Session. Since `requests.Session` is not guaranteed to be thread-safe,
/// `huggingface_hub` creates 1 Session instance per thread. They are all instantiated using the same `backend_factory`
/// set in [`configure_http_backend`]. A LRU cache is used to cache the created sessions (and connections) between
/// calls. Max size is 128 to avoid memory leaks if thousands of threads are spawned.
///
/// See [this issue](https://github.com/psf/requests/issues/2766) to know more about thread-safety in `requests`.
///
/// Example:
/// ```py
/// import requests
/// from huggingface_hub import configure_http_backend, get_session
///
/// # Create a factory function that returns a Session with configured proxies
/// def backend_factory() -> requests.Session:
///     session = requests.Session()
///     session.proxies = {"http": "http://10.10.1.10:3128", "https": "https://10.10.1.11:1080"}
///     return session
///
/// # Set it as the default session factory
/// configure_http_backend(backend_factory=backend_factory)
///
/// # In practice, this is mostly done internally in `huggingface_hub`
/// session = get_session()
/// ```
Dio getSession() {
  return dio;

  // TODO: One day create the cache
  // return _getSessionFromCache(process_id=os.getpid(), thread_id=threading.get_ident());
}

/// Reset the cache of sessions.
///
/// Mostly used internally when sessions are reconfigured or an SSLError is raised.
/// See [`configure_http_backend`] for more details.
void resetSessions() {
  dio = _setupSession();
}

/// Wrapper around requests to retry calls on an endpoint, with exponential backoff.
///
/// Endpoint call is retried on exceptions (ex: connection timeout, proxy error,...)
/// and/or on specific status codes (ex: service unavailable). If the call failed more
/// than `max_retries`, the exception is thrown or `raise_for_status` is called on the
/// response object.
///
/// Re-implement mechanisms from the `backoff` library to avoid adding an external
/// dependencies to `hugging_face_hub`. See https://github.com/litl/backoff.
///
/// Args:
///     method (`Literal["GET", "OPTIONS", "HEAD", "POST", "PUT", "PATCH", "DELETE"]`):
///         HTTP method to perform.
///     url (`str`):
///         The URL of the resource to fetch.
///     max_retries (`int`, *optional*, defaults to `5`):
///         Maximum number of retries, defaults to 5 (no retries).
///     base_wait_time (`float`, *optional*, defaults to `1`):
///         Duration (in seconds) to wait before retrying the first time.
///         Wait time between retries then grows exponentially, capped by
///         `max_wait_time`.
///     max_wait_time (`float`, *optional*, defaults to `8`):
///         Maximum duration (in seconds) to wait before retrying.
///     retry_on_exceptions (`Type[Exception]` or `Tuple[Type[Exception]]`, *optional*):
///         Define which exceptions must be caught to retry the request. Can be a single type or a tuple of types.
///         By default, retry on `requests.Timeout` and `requests.ConnectionError`.
///     retry_on_status_codes (`int` or `Tuple[int]`, *optional*, defaults to `503`):
///         Define on which status codes the request must be retried. By default, only
///         HTTP 503 Service Unavailable is retried.
///     **kwargs (`dict`, *optional*):
///         kwargs to pass to `requests.request`.
///
/// Example:
/// ```
/// >>> from huggingface_hub.utils import http_backoff
///
/// # Same usage as "requests.request".
/// >>> response = http_backoff("GET", "https://www.google.com")
/// >>> response.raise_for_status()
///
/// # If you expect a Gateway Timeout from time to time
/// >>> http_backoff("PUT", upload_url, data=data, retry_on_status_codes=504)
/// >>> response.raise_for_status()
/// ```
///
/// <Tip warning={true}>
///
/// When using `requests` it is possible to stream data by passing an iterator to the
/// `data` argument. On http backoff this is a problem as the iterator is not reset
/// after a failed call. This issue is mitigated for file objects or any IO streams
/// by saving the initial position of the cursor (with `data.tell()`) and resetting the
/// cursor between each call (with `data.seek()`). For arbitrary iterators, http backoff
/// will fail. If this is a hard constraint for you, please let us know by opening an
/// issue on [Github](https://github.com/huggingface/huggingface_hub).
///
/// </Tip>
Future<(Response, void Function())> httpBackoff({
  required String method,
  required String url,
  int maxRetries = 5,
  double baseWaitTime = 1,
  double maxWaitTime = 8,
  List<DioExceptionType> retryOnExceptions = const [DioExceptionType.connectionTimeout, DioExceptionType.connectionError],
  List<int> retryOnStatusCodes = const [503],
  Map<String, dynamic> kwargs = const {},
  Options? dioOptions,
}) async {
  int nbTries = 0;
  double sleepTime = baseWaitTime;

  // If `data` is used and is a file object (or any IO), it will be consumed on the
  // first HTTP request. We need to save the initial position so that the full content
  // of the file is re-sent on http backoff. See warning tip in docstring.
  dynamic ioObjInitialPos;
  if (kwargs.containsKey('data') && kwargs['data'] is File) {
    ioObjInitialPos = await (kwargs['data'] as File).length();
  }

  final Dio session = getSession();
  while (true) {
    ++nbTries;
    try {
      // If `data` is used and is a file object (or any IO), set back cursor to
      // initial position.
      if (ioObjInitialPos != null) {
        // TODO: figure this out...
        // kwargs['data']
      }

      Response? response;
      void Function() raiseForStatus = () {};
      try {
        response = await session.request(
          url,
          options: (dioOptions ?? Options()).copyWith(
            method: method,
          ),
        );
      } on DioException catch (e) {
        response = e.response;
        raiseForStatus = () => throw e;
      }

      // Response info, it may be null if the request can't reach to the HTTP server,
      // for example, occurring a DNS error, network is not available.
      if (response != null) {
        if (!retryOnStatusCodes.contains(response.statusCode)) {
          return (response, raiseForStatus);
        }

        // Wrong status code returned (HTTP 503 for instance)
        print('HTTP Error ${response.statusCode} thrown while requesting $method $url');
      }

      if (nbTries > maxRetries) {
        raiseForStatus(); // Will raise uncaught exception
        // We return response to avoid infinite loop in the corner case where the
        // user ask for retry on a status code that doesn't raise_for_status.
        return (response!, raiseForStatus);
      }
    } catch (err) {
      if (err is DioException && retryOnExceptions.contains(err.type)) {
        print("'$err' thrown while requesting $method $url");

        if (err.type == DioExceptionType.connectionError) {
          // In case of SSLError it's best to reset the shared requests.Session objects
          resetSessions();
        }

        if (nbTries > maxRetries) {
          rethrow;
        }
      }

      rethrow;
    }

    // Sleep for X seconds
    print('Retrying in ${sleepTime}s [Retry $nbTries/$maxRetries].');
    await Future.delayed(Duration(milliseconds: (sleepTime * 1000).truncate()));

    // Update sleep time for next retry
    sleepTime = min(maxWaitTime, sleepTime * 2); // Exponential backoff
  }
}

/// Internal version of `response.raise_for_status()` that will refine a
/// potential HTTPError. Raised exception will be an instance of `HfHubHTTPError`.
///
/// This helper is meant to be the unique method to raise_for_status when making a call
/// to the Hugging Face Hub.
///
///
/// Example:
/// ```py
///     import requests
///     from huggingface_hub.utils import get_session, hf_raise_for_status, HfHubHTTPError
///
///     response = get_session().post(...)
///     try:
///         hf_raise_for_status(response)
///     except HfHubHTTPError as e:
///         print(str(e)) # formatted message
///         e.request_id, e.server_message # details returned by server
///
///         # Complete the error message with additional information once it's raised
///         e.append_to_message("\n`create_commit` expects the repository to exist.")
///         raise
/// ```
///
/// Args:
///     response (`Response`):
///         Response from the server.
///     endpoint_name (`str`, *optional*):
///         Name of the endpoint that has been called. If provided, the error message
///         will be more complete.
///
/// <Tip warning={true}>
///
/// Raises when the request has failed:
///
///     - [`~utils.RepositoryNotFoundError`]
///         If the repository to download from cannot be found. This may be because it
///         doesn't exist, because `repo_type` is not set correctly, or because the repo
///         is `private` and you do not have access.
///     - [`~utils.GatedRepoError`]
///         If the repository exists but is gated and the user is not on the authorized
///         list.
///     - [`~utils.RevisionNotFoundError`]
///         If the repository exists but the revision couldn't be find.
///     - [`~utils.EntryNotFoundError`]
///         If the repository exists but the entry (e.g. the requested file) couldn't be
///         find.
///     - [`~utils.BadRequestError`]
///         If request failed with a HTTP 400 BadRequest error.
///     - [`~utils.HfHubHTTPError`]
///         If request failed for a reason not listed above.
///
/// </Tip>
void hfRaiseForStatus(Response response, void Function() raiseForStatus, [String? endpointName]) {
  try {
    raiseForStatus();
  } on DioException catch (e) {
    final errorCode = response.headers.value('X-Error-Code');
    final errorMessage = response.headers.value('X-Error-Message');

    if (errorCode == 'RevisionNotFound') {
      final message = '${response.statusCode} Client Error.\n\nRevision Not Found for url: ${response.realUri}';
      throw _format(
        (errorMessage, response, serverMessage) => RevisionNotFoundError(errorMessage, response, serverMessage),
        message,
        response,
      );
    } else if (errorCode == 'EntryNotFound') {
      final message = '${response.statusCode} Client Error.\n\nEntry Not Found for url: ${response.realUri}';
      throw _format(
        (errorMessage, response, serverMessage) => EntryNotFoundError(errorMessage, response, serverMessage),
        message,
          response,
      );
    } else if (errorCode == 'GatedRepo') {
      final message = '${response.statusCode} Client Error.\n\nCannot access gated repo for url: ${response.realUri}';
      throw _format(
            (errorMessage, response, serverMessage) => GatedRepoError(errorMessage, response, serverMessage),
        message,
        response,
      );
    } else if (errorMessage == 'Access to this resource is disabled.') {
      final message = '${response.statusCode} Client Error.'
          '\n\n'
          'Cannot access gated repo for url: ${response.realUri}'
          '\n'
          'Access to this resource is disabled.';
      throw _format(
            (errorMessage, response, serverMessage) => DisabledRepoError(errorMessage, response, serverMessage),
        message,
        response,
      );
    } else if (errorCode == 'RepoNotFound' || (
        response.statusCode == 401
            && errorMessage != 'Invalid credentials in Authorization header.'
            && REPO_API_REGEX.hasMatch(response.realUri.toString())
    )) {
      // 401 is misleading as it is returned for:
      //    - private and gated repos if user is not authenticated
      //    - missing repos
      // => for now, we process them as `RepoNotFound` anyway.
      // See https://gist.github.com/Wauplin/46c27ad266b15998ce56a6603796f0b9
      final message = '${response.statusCode} Client Error.'
          '\n\n'
          'Repository Not Found for url: ${response.realUri}'
          "\nPlease make sure you specified the correct `repo_id` and"
          " `repo_type`.\nIf you are trying to access a private or gated repo,"
          " make sure you are authenticated. For more details, see"
          " https://huggingface.co/docs/huggingface_hub/authentication";
      throw _format(
            (errorMessage, response, serverMessage) => RepositoryNotFoundError(errorMessage, response, serverMessage),
        message,
        response,
      );
    } else if (response.statusCode == 400) {
      final message = endpointName != null ? '\n\nBad request for $endpointName endpoint:' : '\n\nBad request:';
      throw _format(
            (errorMessage, response, serverMessage) => BadRequestError(errorMessage, response, serverMessage),
        message,
        response,
      );
    } else if (response.statusCode == 403) {
      final message = "\n\n${response.statusCode} Forbidden: $errorMessage."
          "\nCannot access content at: ${response.realUri}."
          "\nMake sure your token has the correct permissions.";
      throw _format(
            (errorMessage, response, serverMessage) => HfHubHTTPError(errorMessage, response, serverMessage),
        message,
        response,
      );
    } else if (response.statusCode == 416) {
      final rangeHeader = response.headers.value('Range');
      final message = '$e. Requested range: $rangeHeader. Content-Range: ${response.headers.value('Content-Range')}.';
      throw _format(
            (errorMessage, response, serverMessage) => HfHubHTTPError(errorMessage, response, serverMessage),
        message,
        response,
      );
    }
  }
}

HfHubHTTPError _format(
  HfHubHTTPError Function(String errorMessage, Response response, String? serverMessage) errorType,
  String customMessage,
  Response response,
) {
  List<String> serverErrors = [];

  // Retrieve server error from header
  final fromHeaders = response.headers.value('X-Error-Message');
  if (fromHeaders != null) serverErrors.add(fromHeaders);

  // Retrieve server error from body
  try {
    // TODO: Since dio can return different data types we need to check it and convert accordingly
    // Case errors are returned in a JSON format
    final Map<String, dynamic> data = jsonDecode(response.data);

    final error = data['error'];
    if (error != null) {
      if (error is List<String>) {
        // Case {'error': ['my error 1', 'my error 2']}
        serverErrors.addAll(error);
      } else {
        // Case {'error': 'my error'}
        serverErrors.add(error);
      }
    }

    final List<Map<String, dynamic>>? errors = data['errors'];
    if (errors != null) {
      // Case {'errors': [{'message': 'my error 1'}, {'message': 'my error 2'}]}
      for (final error in errors) {
        if (error.containsKey('message')) serverErrors.add(error['message']);
      }
    }
  } catch (e) { // TODO: This is supposed to just catch JSONDecode errors
    // If content is not JSON and not HTML, append the text
    final contentType = response.headers.value('Content-Type') ?? '';
    if (response.data != null && !contentType.toLowerCase().contains('html')) {
      serverErrors.add(response.data);
    }
  }

  // Strip all server messages
  serverErrors = [for (final line in serverErrors) if (line.trim().isNotEmpty) line.trim()];

  // Deduplicate server messages (keep order)
  serverErrors = serverErrors.toSet().toList();

  // Format server error
  final serverMessage = serverErrors.join('\n');

  // Add server error to custom message
  String finalErrorMessage = customMessage;
  if (serverMessage.isNotEmpty && !customMessage.toLowerCase().contains(serverMessage.toLowerCase())) {
    if (customMessage.contains('\n\n')) {
      finalErrorMessage += '\n$serverMessage';
    } else {
      finalErrorMessage += '\n\n$serverMessage';
    }
  }
  // Add Request ID
  final requestId = response.headers.value(X_REQUEST_ID) ?? '';
  late final String requestIdMessage;
  if (requestId.isNotEmpty) {
    requestIdMessage = ' (Request ID: $requestId)';
  } else {
    // Fallback to X-Amzn-Trace-Id
    final requestId = response.headers.value(X_AMZN_TRACE_ID) ?? '';
    if (requestId.isNotEmpty) {
      requestIdMessage = ' (Amzn Trace ID: $requestId)';
    }
  }
  if (requestId.isNotEmpty && !finalErrorMessage.toLowerCase().contains(requestId.toLowerCase())) {
    if (finalErrorMessage.contains('\n')) {
      final newlineIndex = finalErrorMessage.indexOf('\n');
      finalErrorMessage = finalErrorMessage.substring(0, newlineIndex) + requestIdMessage + finalErrorMessage.substring(newlineIndex);
    } else {
      finalErrorMessage += requestIdMessage;
    }
  }

  return errorType(finalErrorMessage.trim(), response, serverMessage.isEmpty ? null : serverMessage);
}

final RegExp RANGE_REGEX = RegExp(r"^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*$", caseSensitive: false);

/// Adjust HTTP Range header to account for resume position.
String? adjustRangeHeader(String? originalRange, int resumeSize) {
  if (originalRange == null) return 'bytes=$resumeSize-';

  if (originalRange.contains(',')) {
    throw ArgumentError("Multiple ranges detected - '$originalRange', not supported yet.");
  }

  final Match? match = RANGE_REGEX.firstMatch(originalRange);
  if (match == null) {
    throw StateError("Invalid range format - '$originalRange'.");
  }

  final String? startStr = match.group(1);
  final String? endStr = match.group(2);

  if (startStr == null || startStr.isEmpty == true) {
    if (endStr == null || endStr.isEmpty) {
      throw StateError("Invalid range format - '$originalRange'.");
    }

    final int newSuffix = int.parse(endStr) - resumeSize;
    final String newRange = 'bytes=-$newSuffix';
    if (newSuffix <= 0) {
      throw StateError("Empty new range - '$newRange'.");
    }
    return newRange;
  }

  final int start = int.parse(startStr);
  final int newStart = start + resumeSize;
  if (endStr != null && endStr.isNotEmpty) {
    final int end = int.parse(endStr);
    final String newRange = 'bytes=$newStart-$end';
    if (newStart > end) {
      throw StateError("Empty new range - '$newRange'.");
    }
    return newRange;
  }

  return 'bytes=$newStart-';
}
