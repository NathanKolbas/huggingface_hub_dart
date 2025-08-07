// HEADERS ERRORS

import 'package:dio/dio.dart';

/// Raised if local token is required but not found.
class LocalTokenNotFoundError implements Exception {
  String cause;

  LocalTokenNotFoundError(this.cause);

  @override
  String toString() {
    return 'LocalTokenNotFoundError: $cause';
  }
}

// HTTP ERRORS

/// Raised when a request is made but `HF_HUB_OFFLINE=1` is set as environment variable.
class OfflineModeIsEnabled implements Exception {
  String cause;

  OfflineModeIsEnabled(this.cause);

  @override
  String toString() {
    return 'OfflineModeIsEnabled: $cause';
  }
}

/// HTTPError to inherit from for any custom HTTP Error raised in HF Hub.
///
/// Any HTTPError is converted at least into a `HfHubHTTPError`. If some information is
/// sent back by the server, it will be added to the error message.
///
/// Added details:
/// - Request id from "X-Request-Id" header if exists. If not, fallback to "X-Amzn-Trace-Id" header if exists.
/// - Server error message from the header "X-Error-Message".
/// - Server error message if we can found one in the response body.
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
class HfHubHTTPError implements Exception {
  static final String clsName = 'HfHubHTTPError';

  String message;

  Response? response;

  String? serverMessage;
  
  String? requestId;

  HfHubHTTPError(this.message, [this.response, this.serverMessage]) {
    requestId = response != null
        ? response!.headers.value('x-request-id') ?? response!.headers.value('X-Amzn-Trace-Id')
        : null;
  }

  void appendToMessage(String additionalMessage) {
   // TODO: What does this even do?
  }

  @override
  String toString() {
    return '$clsName: $message';
  }
}

// FILE METADATA ERRORS

/// Error triggered when the metadata of a file on the Hub cannot be retrieved (missing ETag or commit_hash).
///
/// Inherits from `OSError` for backward compatibility.
class FileMetadataError implements Exception {
  String cause;

  FileMetadataError(this.cause);

  @override
  String toString() {
    return 'FileMetadataError: $cause';
  }
}

// REPOSITORY ERRORS

/// Raised when trying to access a hf.co URL with an invalid repository name, or
/// with a private repo name the user does not have access to.
///
/// Example:
///
/// ```py
/// >>> from huggingface_hub import model_info
/// >>> model_info("<non_existent_repository>")
/// (...)
/// huggingface_hub.utils._errors.RepositoryNotFoundError: 401 Client Error. (Request ID: PvMw_VjBMjVdMz53WKIzP)
///
/// Repository Not Found for url: https://huggingface.co/api/models/%3Cnon_existent_repository%3E.
/// Please make sure you specified the correct `repo_id` and `repo_type`.
/// If the repo is private, make sure you are authenticated.
/// Invalid username or password.
/// ```
class RepositoryNotFoundError extends HfHubHTTPError {
  static final String clsName = 'HfHubHTTPError';

  RepositoryNotFoundError(super.message, [super.response, super.serverMessage]);
}

/// Raised when trying to access a gated repository for which the user is not on the
/// authorized list.
///
/// Note: derives from `RepositoryNotFoundError` to ensure backward compatibility.
///
/// Example:
///
/// ```py
/// >>> from huggingface_hub import model_info
/// >>> model_info("<gated_repository>")
/// (...)
/// huggingface_hub.utils._errors.GatedRepoError: 403 Client Error. (Request ID: ViT1Bf7O_026LGSQuVqfa)
///
/// Cannot access gated repo for url https://huggingface.co/api/models/ardent-figment/gated-model.
/// Access to model ardent-figment/gated-model is restricted and you are not in the authorized list.
/// Visit https://huggingface.co/ardent-figment/gated-model to ask for access.
/// ```
class GatedRepoError extends RepositoryNotFoundError {
  static final String clsName = 'GatedRepoError';

  GatedRepoError(super.message, [super.response, super.serverMessage]);
}

/// Raised when trying to access a repository that has been disabled by its author.
///
/// Example:
///
/// ```py
/// >>> from huggingface_hub import dataset_info
/// >>> dataset_info("laion/laion-art")
/// (...)
/// huggingface_hub.utils._errors.DisabledRepoError: 403 Client Error. (Request ID: Root=1-659fc3fa-3031673e0f92c71a2260dbe2;bc6f4dfb-b30a-4862-af0a-5cfe827610d8)
///
/// Cannot access repository for url https://huggingface.co/api/datasets/laion/laion-art.
/// Access to this resource is disabled.
/// ```
class DisabledRepoError extends RepositoryNotFoundError {
  static final String clsName = 'DisabledRepoError';

  DisabledRepoError(super.message, [super.response, super.serverMessage]);
}

// REVISION ERROR

/// Raised when trying to access a hf.co URL with a valid repository but an invalid
/// revision.
///
/// Example:
///
/// ```py
/// >>> from huggingface_hub import hf_hub_download
/// >>> hf_hub_download('bert-base-cased', 'config.json', revision='<non-existent-revision>')
/// (...)
/// huggingface_hub.utils._errors.RevisionNotFoundError: 404 Client Error. (Request ID: Mwhe_c3Kt650GcdKEFomX)
///
/// Revision Not Found for url: https://huggingface.co/bert-base-cased/resolve/%3Cnon-existent-revision%3E/config.json.
/// ```
class RevisionNotFoundError extends HfHubHTTPError {
  static final String clsName = 'RevisionNotFoundError';

  RevisionNotFoundError(super.message, [super.response, super.serverMessage]);
}

// ENTRY ERRORS

/// Raised when trying to access a hf.co URL with a valid repository and revision
/// but an invalid filename.
///
/// Example:
///
/// ```py
/// >>> from huggingface_hub import hf_hub_download
/// >>> hf_hub_download('bert-base-cased', '<non-existent-file>')
/// (...)
/// huggingface_hub.utils._errors.EntryNotFoundError: 404 Client Error. (Request ID: 53pNl6M0MxsnG5Sw8JA6x)
///
/// Entry Not Found for url: https://huggingface.co/bert-base-cased/resolve/main/%3Cnon-existent-file%3E.
/// ```
class EntryNotFoundError extends HfHubHTTPError {
  static final String clsName = 'EntryNotFoundError';

  EntryNotFoundError(super.message, [super.response, super.serverMessage]);
}

/// Raised when trying to access a file or snapshot that is not on the disk when network is
/// disabled or unavailable (connection issue). The entry may exist on the Hub.
///
/// Note: `ValueError` type is to ensure backward compatibility.
/// Note: `LocalEntryNotFoundError` derives from `HTTPError` because of `EntryNotFoundError`
/// even when it is not a network issue.
///
/// Example:
///
/// ```py
/// >>> from huggingface_hub import hf_hub_download
/// >>> hf_hub_download('bert-base-cased', '<non-cached-file>',  local_files_only=True)
/// (...)
/// huggingface_hub.utils._errors.LocalEntryNotFoundError: Cannot find the requested files in the disk cache and outgoing traffic has been disabled. To enable hf.co look-ups and downloads online, set 'local_files_only' to False.
/// ```
class LocalEntryNotFoundError extends EntryNotFoundError {
  static final String clsName = 'LocalEntryNotFoundError';

  LocalEntryNotFoundError(super.message, [super.response, super.serverMessage]);
}

// REQUEST ERROR

/// Raised by `hf_raise_for_status` when the server returns a HTTP 400 error.
///
/// Example:
///
/// ```py
/// >>> resp = requests.post("hf.co/api/check", ...)
/// >>> hf_raise_for_status(resp, endpoint_name="check")
/// huggingface_hub.utils._errors.BadRequestError: Bad request for check endpoint: {details} (Request ID: XXX)
/// ```
class BadRequestError extends HfHubHTTPError {
  static final String clsName = 'BadRequestError';

  BadRequestError(super.message, [super.response, super.serverMessage]);
}
