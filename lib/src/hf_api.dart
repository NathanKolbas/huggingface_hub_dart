import 'package:dio/dio.dart';
import 'package:huggingface_hub/src/_headers.dart';
import 'package:huggingface_hub/src/_http.dart';
import 'package:huggingface_hub/src/constants.dart' as constants;
import 'package:huggingface_hub/src/repocard_data.dart';
import 'package:huggingface_hub/src/utils/_pagination.dart';
import 'package:huggingface_hub/src/utils/python_to_dart.dart';

import '_space_api.dart';

enum ExpandModelProperty {
  author,
  baseModels,
  cardData,
  childrenModelCount,
  config,
  createdAt,
  disabled,
  downloads,
  downloadsAllTime,
  gated,
  gguf,
  inference,
  inferenceProviderMapping,
  lastModified,
  library_name,
  likes,
  mask_token,
  model,
  pipeline_tag,
  private,
  resourceGroup,
  safetensors,
  sha,
  siblings,
  spaces,
  tags,
  transformersInfo,
  trendingScore,
  usedStorage,
  widgetData,
  xetEnabled;

  String toJson() => name;

  factory ExpandModelProperty.fromJson(String value) => values.byName(value);
}

enum ExpandDatasetProperty {
  author,
  cardData,
  citation,
  createdAt,
  description,
  disabled,
  downloads,
  downloadsAllTime,
  gated,
  lastModified,
  likes,
  paperswithcode_id,
  private,
  resourceGroup,
  sha,
  siblings,
  tags,
  trendingScore,
  usedStorage,
  xetEnabled;

  String toJson() => name;

  factory ExpandDatasetProperty.fromJson(String value) => values.byName(value);
}

enum ExpandSpaceProperty {
  author,
  cardData,
  createdAt,
  datasets,
  disabled,
  lastModified,
  likes,
  models,
  private,
  resourceGroup,
  runtime,
  sdk,
  sha,
  siblings,
  subdomain,
  tags,
  trendingScore,
  usedStorage,
  xetEnabled;

  String toJson() => name;

  factory ExpandSpaceProperty.fromJson(String value) => values.byName(value);
}

/// This allows for type-safe handling of different property enums in a single list.
sealed class ExpandProperty {
  /// Converts the property to its JSON string representation for the API.
  String toJson();
}

class ExpandModel extends ExpandProperty {
  final ExpandModelProperty value;

  ExpandModel(this.value);

  @override
  String toJson() => value.name;
}

class ExpandDataset extends ExpandProperty {
  final ExpandDatasetProperty value;

  ExpandDataset(this.value);

  @override
  String toJson() => value.name;
}

class ExpandSpace extends ExpandProperty {
  final ExpandSpaceProperty value;

  ExpandSpace(this.value);

  @override
  String toJson() => value.name;
}

// @dataclass
class LastCommitInfo {
  final String oid;
  final String title;
  final DateTime date;

  LastCommitInfo({
    required this.oid,
    required this.title,
    required this.date,
  });
}

// @dataclass
class BlobLfsInfo {
  int size;
  String sha256;
  int pointerSize;

  BlobLfsInfo({
    required this.size,
    required this.sha256,
    required this.pointerSize,
  });

  factory BlobLfsInfo.fromJson(Map<String, dynamic> json) => BlobLfsInfo(
    size: json['size'],
    sha256: json['sha256'],
    pointerSize: json['pointerSize'],
  );
}

// @dataclass
class BlobSecurityInfo {
  final bool safe; // duplicate information with "status" field, keeping it for backward compatibility
  final String status;
  final Map<String, dynamic>? avScan;
  final Map<String, dynamic>? pickleImportScan;

  BlobSecurityInfo({
    required this.safe,
    required this.status,
    this.avScan,
    this.pickleImportScan,
  });
}

// @dataclass
class TransformersInfo {
  String autoModel;
  String? customClass;
  /// possible `pipeline_tag` values: https://github.com/huggingface/huggingface.js/blob/3ee32554b8620644a6287e786b2a83bf5caf559c/packages/tasks/src/pipelines.ts#L72
  String? pipelineTag;
  String? processor;

  TransformersInfo({
    required this.autoModel,
    this.customClass,
    this.pipelineTag,
    this.processor,
  });

  factory TransformersInfo.fromJson(Map<String, dynamic> json) => TransformersInfo(
    autoModel: json['auto_model'],
    customClass: json['custom_class'],
    pipelineTag: json['pipeline_tag'],
    processor: json['processor'],
  );
}

// @dataclass
class SafeTensorsInfo {
  Map<String, int> parameters;
  int total;

  SafeTensorsInfo({
    required this.parameters,
    required this.total,
  });

  factory SafeTensorsInfo.fromJson(Map<String, dynamic> json) => SafeTensorsInfo(
    parameters: json['parameters'],
    total: json['total'],
  );
}

/// Contains basic information about a repo file inside a repo on the Hub.
///
/// <Tip>
///
/// All attributes of this class are optional except `rfilename`. This is because only the file names are returned when
/// listing repositories on the Hub (with [`list_models`], [`list_datasets`] or [`list_spaces`]). If you need more
/// information like file size, blob id or lfs details, you must request them specifically from one repo at a time
/// (using [`model_info`], [`dataset_info`] or [`space_info`]) as it adds more constraints on the backend server to
/// retrieve these.
///
/// </Tip>
///
/// Attributes:
///     rfilename (str):
///         file name, relative to the repo root.
///     size (`int`, *optional*):
///         The file's size, in bytes. This attribute is defined when `files_metadata` argument of [`repo_info`] is set
///         to `True`. It's `None` otherwise.
///     blob_id (`str`, *optional*):
///         The file's git OID. This attribute is defined when `files_metadata` argument of [`repo_info`] is set to
///         `True`. It's `None` otherwise.
///     lfs (`BlobLfsInfo`, *optional*):
///         The file's LFS metadata. This attribute is defined when`files_metadata` argument of [`repo_info`] is set to
///         `True` and the file is stored with Git LFS. It's `None` otherwise.
// @dataclass
class RepoSibling {
  String rfilename;
  int? size;
  String? blobId;
  BlobLfsInfo? lfs;

  RepoSibling({
    required this.rfilename,
    this.size,
    this.blobId,
    this.lfs,
});

  factory RepoSibling.fromJson(Map<String, dynamic> json) => RepoSibling(
    rfilename: json['rfilename'],
    size: json['size'],
    blobId: json['blobId'],
    lfs: json['lfs'] != null ? BlobLfsInfo.fromJson(json['lfs']) : null,
  );
}

sealed class RepoFileOrFolder {}

/// Contains information about a file on the Hub.
///
/// Attributes:
///     path (str):
///         file path relative to the repo root.
///     size (`int`):
///         The file's size, in bytes.
///     blob_id (`str`):
///         The file's git OID.
///     lfs (`BlobLfsInfo`):
///         The file's LFS metadata.
///     last_commit (`LastCommitInfo`, *optional*):
///         The file's last commit metadata. Only defined if [`list_repo_tree`] and [`get_paths_info`]
///         are called with `expand=True`.
///     security (`BlobSecurityInfo`, *optional*):
///         The file's security scan metadata. Only defined if [`list_repo_tree`] and [`get_paths_info`]
///         are called with `expand=True`.
// @dataclass
class RepoFile extends RepoFileOrFolder {
  late final String path;
  late final int size;
  late final String blobId;
  late final BlobLfsInfo? lfs;
  late final LastCommitInfo? lastCommit;
  late final BlobSecurityInfo? security;

  // backwards compatibility

  late final String rfilename;

  RepoFile(Map<String, dynamic> kwargs) {
    path = kwargs.remove('provider');
    size = kwargs.remove('size');
    blobId = kwargs.remove('oid');
    final lfs = kwargs.remove('lfs');
    if (lfs != null) {
      this.lfs = BlobLfsInfo(size: lfs['size'], sha256: lfs['oid'], pointerSize: lfs['pointerSize']);
    }
    final lastCommit = kwargs.remove('lastCommit') ?? kwargs.remove('last_commit');
    if (lastCommit != null) {
      this.lastCommit = LastCommitInfo(
        oid: lastCommit["id"],
        title: lastCommit["title"],
        date: DateTime.parse(lastCommit["date"]),
      );
    }
    final security = kwargs.remove('securityFileStatus');
    if (security != null) {
      this.security = BlobSecurityInfo(
        safe: security['status'] == 'safe',
        status: security['status'],
        avScan: security['avScan'],
        pickleImportScan: security['pickleImportScan'],
      );
    }

    // backwards compatibility
    rfilename = path;
  }

  factory RepoFile.fromJson(Map<String, dynamic> json) => RepoFile(json);
}

/// Contains information about a folder on the Hub.
///
/// Attributes:
///     path (str):
///         folder path relative to the repo root.
///     tree_id (`str`):
///         The folder's git OID.
///     last_commit (`LastCommitInfo`, *optional*):
///         The folder's last commit metadata. Only defined if [`list_repo_tree`] and [`get_paths_info`]
///         are called with `expand=True`.
// @dataclass
class RepoFolder extends RepoFileOrFolder {
  late final String path;
  late final String treeId;
  late final LastCommitInfo? lastCommit;

  RepoFolder(Map<String, dynamic> kwargs) {
    path = kwargs.remove('provider');
    treeId = kwargs.remove('oid');
    final lastCommit = kwargs.remove('lastCommit') ?? kwargs.remove('last_commit');
    if (lastCommit != null) {
      this.lastCommit = LastCommitInfo(
        oid: lastCommit["id"],
        title: lastCommit["title"],
        date: DateTime.parse(lastCommit["date"]),
      );
    }
  }

  factory RepoFolder.fromJson(Map<String, dynamic> json) => RepoFolder(json);
}

// @dataclass
class InferenceProviderMapping {
  late final Map<String, dynamic> dict;

  /// Provider name
  late String provider;
  /// ID of the model on the Hugging Face Hub
  late String hfModelId;
  /// ID of the model on the provider's side
  late String providerId;
  late String status;
  late String task;

  late String? adapter;
  late String? adapterWeightsPath;
  late String? type;

  InferenceProviderMapping(Map<String, dynamic> data) {
    provider = data.remove('provider');
    hfModelId = data.remove('hf_model_id');
    providerId = data.remove('providerId');
    status = data.remove('status');
    task = data.remove('task');

    adapter = data.remove('adapter');
    adapterWeightsPath = data.remove('adapterWeightsPath');
    type = data.remove('type');
    dict = data;
  }

  factory InferenceProviderMapping.fromJson(Map<String, dynamic> json) => InferenceProviderMapping(json);
}

sealed class RepoInfoBase {}

/// Contains information about a model on the Hub. This object is returned by [`model_info`] and [`list_models`].
///
/// <Tip>
///
/// Most attributes of this class are optional. This is because the data returned by the Hub depends on the query made.
/// In general, the more specific the query, the more information is returned. On the contrary, when listing models
/// using [`list_models`] only a subset of the attributes are returned.
///
/// </Tip>
///
/// Attributes:
///     id (`str`):
///         ID of model.
///     author (`str`, *optional*):
///         Author of the model.
///     sha (`str`, *optional*):
///         Repo SHA at this particular revision.
///     created_at (`datetime`, *optional*):
///         Date of creation of the repo on the Hub. Note that the lowest value is `2022-03-02T23:29:04.000Z`,
///         corresponding to the date when we began to store creation dates.
///     last_modified (`datetime`, *optional*):
///         Date of last commit to the repo.
///     private (`bool`):
///         Is the repo private.
///     disabled (`bool`, *optional*):
///         Is the repo disabled.
///     downloads (`int`):
///         Number of downloads of the model over the last 30 days.
///     downloads_all_time (`int`):
///         Cumulated number of downloads of the model since its creation.
///     gated (`Literal["auto", "manual", False]`, *optional*):
///         Is the repo gated.
///         If so, whether there is manual or automatic approval.
///     gguf (`Dict`, *optional*):
///         GGUF information of the model.
///     inference (`Literal["warm"]`, *optional*):
///         Status of the model on Inference Providers. Warm if the model is served by at least one provider.
///     inference_provider_mapping (`List[InferenceProviderMapping]`, *optional*):
///         A list of [`InferenceProviderMapping`] ordered after the user's provider order.
///     likes (`int`):
///         Number of likes of the model.
///     library_name (`str`, *optional*):
///         Library associated with the model.
///     tags (`List[str]`):
///         List of tags of the model. Compared to `card_data.tags`, contains extra tags computed by the Hub
///         (e.g. supported libraries, model's arXiv).
///     pipeline_tag (`str`, *optional*):
///         Pipeline tag associated with the model.
///     mask_token (`str`, *optional*):
///         Mask token used by the model.
///     widget_data (`Any`, *optional*):
///         Widget data associated with the model.
///     model_index (`Dict`, *optional*):
///         Model index for evaluation.
///     config (`Dict`, *optional*):
///         Model configuration.
///     transformers_info (`TransformersInfo`, *optional*):
///         Transformers-specific info (auto class, processor, etc.) associated with the model.
///     trending_score (`int`, *optional*):
///         Trending score of the model.
///     card_data (`ModelCardData`, *optional*):
///         Model Card Metadata  as a [`huggingface_hub.repocard_data.ModelCardData`] object.
///     siblings (`List[RepoSibling]`):
///         List of [`huggingface_hub.hf_api.RepoSibling`] objects that constitute the model.
///     spaces (`List[str]`, *optional*):
///         List of spaces using the model.
///     safetensors (`SafeTensorsInfo`, *optional*):
///         Model's safetensors information.
///     security_repo_status (`Dict`, *optional*):
///         Model's security scan status.
// @dataclass
class ModelInfo extends RepoInfoBase {
  late final Map<String, dynamic> dict;

  late final String id;
  late final String? author;
  late final String? sha;
  late final DateTime? createdAt;
  late final DateTime? lastModified;
  late final bool? private;
  late final bool? disabled;
  late final int? downloads;
  late final int? downloadsAllTime;
  /// Literal["auto", "manual", False]
  late final dynamic gated;
  late final Map<String, dynamic>? gguf;
  /// Literal["warm"]
  late final String? inference;
  late final List<InferenceProviderMapping>? inferenceProviderMapping;
  late final int? likes;
  late final String? libraryName;
  late final List<String>? tags;
  late final String? pipelineTag;
  late final String? maskToken;
  late final ModelCardData? cardData;
  late final dynamic widgetData;
  late final Map<String, dynamic>? modelIndex;
  late final Map<String, dynamic>? config;
  late final TransformersInfo? transformersInfo;
  late final int? trendingScore;
  late final List<RepoSibling>? siblings;
  late final List<String>? spaces;
  late final SafeTensorsInfo? safetensors;
  late final Map<String, dynamic>? securityRepoStatus;
  late final bool? xetEnabled;

  ModelInfo(Map<String, dynamic> data) {
    id = data.remove('id');
    author = data.remove('author');
    sha = data.remove('sha');
    final lastModified = data.remove('lastModified') ?? data.remove('last_modified');
    this.lastModified = lastModified != null ? DateTime.parse(lastModified) : null;
    final createdAt = data.remove('createdAt') ?? data.remove('created_at');
    this.createdAt = createdAt != null ? DateTime.parse(createdAt) : null;
    private = data.remove('private');
    gated = data.remove('gated');
    disabled = data.remove('disabled');
    downloads = data.remove('downloads');
    downloadsAllTime = data.remove('downloadsAllTime');
    likes = data.remove('likes');
    libraryName = data.remove('library_name');
    gguf = data.remove('gguf');

    inference = data.remove('inference');

    // little hack to simplify Inference Providers logic and make it backward and forward compatible
    // right now, API returns a dict on model_info and a list on list_models. Let's harmonize to list.
    final mapping = data.remove('inferenceProviderMapping');
    if (mapping is List) {
      inferenceProviderMapping = [for (final value in mapping) InferenceProviderMapping.fromJson({...value, 'hf_model_id': id})];
    } else if (mapping is Map) {
      inferenceProviderMapping = [
        for (final value in mapping.entries)
          InferenceProviderMapping.fromJson({...value.value, 'hf_model_id': id, 'provider': value.key})
      ];
    } else if (mapping == null) {
      inferenceProviderMapping = null;
    } else {
      throw ArgumentError('Unexpected type for `inferenceProviderMapping`. Expecting `dict` or `list`. Got $mapping.');
    }

    tags = data['tags'] != null ?  List<String>.from(data.remove('tags')) : null;
    pipelineTag = data.remove('pipeline_tag');
    maskToken = data.remove('mask_token');
    trendingScore = data.remove('trendingScore');

    final cardData = data.remove('cardData') ?? data.remove('card_data');
    this.cardData = cardData is Map<String, dynamic> ? ModelCardData.fromJson(cardData, ignoreMetadataErrors: true) : cardData;

    widgetData = data.remove('widgetData');
    modelIndex = data.remove('model-index') ?? data.remove('model_index');
    config = data.remove('config');
    final transformersInfo = data.remove('transformersInfo') ?? data.remove('transformers_info');
    this.transformersInfo = transformersInfo != null ? TransformersInfo.fromJson(transformersInfo) : null;
    final siblings = data.remove('siblings');
    this.siblings = siblings != null
      ? [for (final sibling in siblings) RepoSibling.fromJson(sibling)]
      : null;
    spaces = data['spaces'] != null ? List<String>.from(data.remove('spaces')) : null;
    final safetensors = data.remove('safetensors');
    this.safetensors = safetensors != null
      ? SafeTensorsInfo.fromJson(safetensors)
      : null;
    securityRepoStatus = data.remove('securityRepoStatus');
    xetEnabled = data.remove('xetEnabled');
    dict = data;
  }

  factory ModelInfo.fromJson(Map<String, dynamic> data) => ModelInfo(data);
}

/// Contains information about a dataset on the Hub. This object is returned by [`dataset_info`] and [`list_datasets`].
///
/// <Tip>
///
/// Most attributes of this class are optional. This is because the data returned by the Hub depends on the query made.
/// In general, the more specific the query, the more information is returned. On the contrary, when listing datasets
/// using [`list_datasets`] only a subset of the attributes are returned.
///
/// </Tip>
///
/// Attributes:
///     id (`str`):
///         ID of dataset.
///     author (`str`):
///         Author of the dataset.
///     sha (`str`):
///         Repo SHA at this particular revision.
///     created_at (`datetime`, *optional*):
///         Date of creation of the repo on the Hub. Note that the lowest value is `2022-03-02T23:29:04.000Z`,
///         corresponding to the date when we began to store creation dates.
///     last_modified (`datetime`, *optional*):
///         Date of last commit to the repo.
///     private (`bool`):
///         Is the repo private.
///     disabled (`bool`, *optional*):
///         Is the repo disabled.
///     gated (`Literal["auto", "manual", False]`, *optional*):
///         Is the repo gated.
///         If so, whether there is manual or automatic approval.
///     downloads (`int`):
///         Number of downloads of the dataset over the last 30 days.
///     downloads_all_time (`int`):
///         Cumulated number of downloads of the model since its creation.
///     likes (`int`):
///         Number of likes of the dataset.
///     tags (`List[str]`):
///         List of tags of the dataset.
///     card_data (`DatasetCardData`, *optional*):
///         Model Card Metadata  as a [`huggingface_hub.repocard_data.DatasetCardData`] object.
///     siblings (`List[RepoSibling]`):
///         List of [`huggingface_hub.hf_api.RepoSibling`] objects that constitute the dataset.
///     paperswithcode_id (`str`, *optional*):
///         Papers with code ID of the dataset.
///     trending_score (`int`, *optional*):
///         Trending score of the dataset.
// @dataclass
class DatasetInfo extends RepoInfoBase {
  late final Map<String, dynamic> dict;

  late final String id;
  late final String? author;
  late final String? sha;
  late final DateTime? createdAt;
  late final DateTime? lastModified;
  late final bool? private;
  /// Literal["auto", "manual", False]
  late final dynamic gated;
  late final bool? disabled;
  late final int? downloads;
  late final int? downloadsAllTime;
  late final int? likes;
  late final String? paperswithcodeId;
  late final List<String>? tags;
  late final int? trendingScore;
  late final DatasetCardData? cardData;
  late final List<RepoSibling>? siblings;
  late final bool? xetEnabled;

  DatasetInfo(Map<String, dynamic> data) {
    id = data.remove('id');
    author = data.remove('author');
    sha = data.remove('sha');
    final createdAt = data.remove('createdAt') ?? data.remove('created_at');
    this.createdAt = createdAt != null ? DateTime.parse(createdAt) : null;
    final lastModified = data.remove('lastModified') ?? data.remove('last_modified');
    this.lastModified = lastModified != null ? DateTime.parse(lastModified) : null;
    private = data.remove('private');
    gated = data.remove('gated');
    disabled = data.remove('disabled');
    downloads = data.remove('downloads');
    downloadsAllTime = data.remove('downloadsAllTime');
    likes = data.remove('likes');
    paperswithcodeId = data.remove('paperswithcode_id');
    tags = data.remove('tags');
    trendingScore = data.remove('trendingScore');

    final cardData = data.remove('cardData') ?? data.remove('card_data');
    this.cardData = cardData is Map<String, dynamic> ? DatasetCardData.fromJson(cardData, ignoreMetadataErrors: true) : cardData;
    final siblings = data.remove('siblings');
    this.siblings = siblings != null
        ? [for (final sibling in siblings) RepoSibling.fromJson(sibling)]
        : null;
    xetEnabled = data.remove('xetEnabled');
    dict = data;
  }

  factory DatasetInfo.fromJson(Map<String, dynamic> data) => DatasetInfo(data);
}

/// Contains information about a Space on the Hub. This object is returned by [`space_info`] and [`list_spaces`].
///
/// <Tip>
///
/// Most attributes of this class are optional. This is because the data returned by the Hub depends on the query made.
/// In general, the more specific the query, the more information is returned. On the contrary, when listing spaces
/// using [`list_spaces`] only a subset of the attributes are returned.
///
/// </Tip>
///
/// Attributes:
///     id (`str`):
///         ID of the Space.
///     author (`str`, *optional*):
///         Author of the Space.
///     sha (`str`, *optional*):
///         Repo SHA at this particular revision.
///     created_at (`datetime`, *optional*):
///         Date of creation of the repo on the Hub. Note that the lowest value is `2022-03-02T23:29:04.000Z`,
///         corresponding to the date when we began to store creation dates.
///     last_modified (`datetime`, *optional*):
///         Date of last commit to the repo.
///     private (`bool`):
///         Is the repo private.
///     gated (`Literal["auto", "manual", False]`, *optional*):
///         Is the repo gated.
///         If so, whether there is manual or automatic approval.
///     disabled (`bool`, *optional*):
///         Is the Space disabled.
///     host (`str`, *optional*):
///         Host URL of the Space.
///     subdomain (`str`, *optional*):
///         Subdomain of the Space.
///     likes (`int`):
///         Number of likes of the Space.
///     tags (`List[str]`):
///         List of tags of the Space.
///     siblings (`List[RepoSibling]`):
///         List of [`huggingface_hub.hf_api.RepoSibling`] objects that constitute the Space.
///     card_data (`SpaceCardData`, *optional*):
///         Space Card Metadata  as a [`huggingface_hub.repocard_data.SpaceCardData`] object.
///     runtime (`SpaceRuntime`, *optional*):
///         Space runtime information as a [`huggingface_hub.hf_api.SpaceRuntime`] object.
///     sdk (`str`, *optional*):
///         SDK used by the Space.
///     models (`List[str]`, *optional*):
///         List of models used by the Space.
///     datasets (`List[str]`, *optional*):
///         List of datasets used by the Space.
///     trending_score (`int`, *optional*):
///         Trending score of the Space.
// @dataclass
class SpaceInfo extends RepoInfoBase {
  late final Map<String, dynamic> dict;

  late final String id;
  late final String? author;
  late final String? sha;
  late final DateTime? createdAt;
  late final DateTime? lastModified;
  late final bool? private;
  /// Literal["auto", "manual", False]
  late final dynamic gated;
  late final bool? disabled;
  late final String? host;
  late final String? subdomain;
  late final int? likes;
  late final String? sdk;
  late final List<String>? tags;
  late final List<RepoSibling>? siblings;
  late final int? trendingScore;
  late final SpaceCardData? cardData;
  late final SpaceRuntime? runtime;
  late final List<String>? models;
  late final List<String>? datasets;
  late final bool? xetEnabled;

  SpaceInfo(Map<String, dynamic> data) {
    id = data.remove('id');
    author = data.remove('author');
    sha = data.remove('sha');
    final createdAt = data.remove('createdAt') ?? data.remove('created_at');
    this.createdAt = createdAt != null ? DateTime.parse(createdAt) : null;
    final lastModified = data.remove('lastModified') ?? data.remove('last_modified');
    this.lastModified = lastModified != null ? DateTime.parse(lastModified) : null;
    private = data.remove('private');
    gated = data.remove('gated');
    disabled = data.remove('disabled');
    host = data.remove('host');
    subdomain = data.remove('subdomain');
    likes = data.remove('likes');
    sdk = data.remove('sdk');
    tags = data.remove('tags');
    trendingScore = data.remove('trendingScore');
    final cardData = data.remove('cardData') ?? data.remove('card_data');
    this.cardData = cardData is Map<String, dynamic> ? SpaceCardData.fromJson(cardData, ignoreMetadataErrors: true) : cardData;
    final siblings = data.remove('siblings');
    this.siblings = siblings != null
        ? [for (final sibling in siblings) RepoSibling.fromJson(sibling)]
        : null;
    final runtime = data.remove('runtime');
    this.runtime = runtime != null ? SpaceRuntime.fromJson(runtime) : null;
    models = data.remove('models');
    datasets = data.remove('datasets');
    xetEnabled = data.remove('xetEnabled');
    dict = data;
  }

  factory SpaceInfo.fromJson(Map<String, dynamic> data) => SpaceInfo(data);
}

/// Client to interact with the Hugging Face Hub via HTTP.
///
/// The client is initialized with some high-level settings used in all requests
/// made to the Hub (HF endpoint, authentication, user agents...). Using the `HfApi`
/// client is preferred but not mandatory as all of its public methods are exposed
/// directly at the root of `huggingface_hub`.
///
/// Args:
///     endpoint (`str`, *optional*):
///         Endpoint of the Hub. Defaults to <https://huggingface.co>.
///     token (Union[bool, str, None], optional):
///         A valid user access token (string). Defaults to the locally saved
///         token, which is the recommended method for authentication (see
///         https://huggingface.co/docs/huggingface_hub/quick-start#authentication).
///         To disable authentication, pass `False`.
///     library_name (`str`, *optional*):
///         The name of the library that is making the HTTP request. Will be added to
///         the user-agent header. Example: `"transformers"`.
///     library_version (`str`, *optional*):
///         The version of the library that is making the HTTP request. Will be added
///         to the user-agent header. Example: `"4.24.0"`.
///     user_agent (`str`, `dict`, *optional*):
///         The user agent info in the form of a dictionary or a single string. It will
///         be completed with information about the installed packages.
///     headers (`dict`, *optional*):
///         Additional headers to be sent with each request. Example: `{"X-My-Header": "value"}`.
///         Headers passed here are taking precedence over the default headers.
class HfApi {
  String? endpoint = constants.ENDPOINT;

  dynamic token;

  String? libraryName;

  String? libraryVersion;

  dynamic userAgent;

  Map<String, String>? headers;

  dynamic _threadPool;

  HfApi({
    this.endpoint,
    this.token,
    this.libraryName,
    this.libraryVersion,
    this.userAgent,
    this.headers,
  }) {
    endpoint ??= constants.ENDPOINT;
  }

  /// Get info on one specific model on huggingface.co
  ///
  /// Model can be private if you pass an acceptable token or are logged in.
  ///
  /// Args:
  ///     repo_id (`str`):
  ///         A namespace (user or an organization) and a repo name separated
  ///         by a `/`.
  ///     revision (`str`, *optional*):
  ///         The revision of the model repository from which to get the
  ///         information.
  ///     timeout (`float`, *optional*):
  ///         Whether to set a timeout for the request to the Hub.
  ///     securityStatus (`bool`, *optional*):
  ///         Whether to retrieve the security status from the model
  ///         repository as well. The security status will be returned in the `security_repo_status` field.
  ///     files_metadata (`bool`, *optional*):
  ///         Whether or not to retrieve metadata for files in the repository
  ///         (size, LFS metadata, etc). Defaults to `False`.
  ///     expand (`List[ExpandModelProperty_T]`, *optional*):
  ///         List properties to return in the response. When used, only the properties in the list will be returned.
  ///         This parameter cannot be used if `securityStatus` or `files_metadata` are passed.
  ///         Possible values are `"author"`, `"baseModels"`, `"cardData"`, `"childrenModelCount"`, `"config"`, `"createdAt"`, `"disabled"`, `"downloads"`, `"downloadsAllTime"`, `"gated"`, `"gguf"`, `"inference"`, `"inferenceProviderMapping"`, `"lastModified"`, `"library_name"`, `"likes"`, `"mask_token"`, `"model-index"`, `"pipeline_tag"`, `"private"`, `"safetensors"`, `"sha"`, `"siblings"`, `"spaces"`, `"tags"`, `"transformersInfo"`, `"trendingScore"`, `"widgetData"`, `"usedStorage"`, `"resourceGroup"` and `"xetEnabled"`.
  ///     token (Union[bool, str, None], optional):
  ///         A valid user access token (string). Defaults to the locally saved
  ///         token, which is the recommended method for authentication (see
  ///         https://huggingface.co/docs/huggingface_hub/quick-start#authentication).
  ///         To disable authentication, pass `False`.
  ///
  /// Returns:
  ///     [`huggingface_hub.hf_api.ModelInfo`]: The model repository information.
  ///
  /// <Tip>
  ///
  /// Raises the following errors:
  ///
  ///     - [`~utils.RepositoryNotFoundError`]
  ///       If the repository to download from cannot be found. This may be because it doesn't exist,
  ///       or because it is set to `private` and you do not have access.
  ///     - [`~utils.RevisionNotFoundError`]
  ///       If the revision to download from cannot be found.
  ///
  /// </Tip>
  Future<ModelInfo> modelInfo(
    String repoId,
    {
      String? revision,
      double? timeout,
      bool? securityStatus,
      bool filesMetadata = false,
      // List<ExpandModelProperty>? expand,
      List<ExpandProperty>? expand,
      dynamic token,
    }
  ) async {
    if (expand != null && (securityStatus == true || filesMetadata)) {
      throw ArgumentError('`expand` cannot be used if `securityStatus` or `files_metadata` are set.');
    }

    final headers = await _buildHfHeaders(token: token);
    final path = revision == null
        ? '$endpoint/api/models/$repoId'
        : '$endpoint/api/models/$repoId/revision/${Uri.encodeFull(revision).replaceAll('/', '%2F')}';
    final Map<String, dynamic> params = {};
    if (securityStatus == true) {
      params['securityStatus'] = true;
    }
    if (filesMetadata) {
      params['blobs'] = true;
    }
    if (expand != null) {
      params['expand'] = expand;
    }
    final (r, raiseForStatus) = await raiseForStatusDioWrapper(() async {
      return await getSession().get(
        path,
        queryParameters: params,
        options: Options(
          responseType: ResponseType.json,
          headers: headers,
          receiveTimeout: timeout != null ? Duration(milliseconds: (timeout * 1000).toInt()) : null,
        ),
      );
    });
    hfRaiseForStatus(r, raiseForStatus);
    return ModelInfo.fromJson(r.data);
  }

  /// Get info on one specific dataset on huggingface.co.
  ///
  /// Dataset can be private if you pass an acceptable token.
  ///
  /// Args:
  ///     repo_id (`str`):
  ///         A namespace (user or an organization) and a repo name separated
  ///         by a `/`.
  ///     revision (`str`, *optional*):
  ///         The revision of the dataset repository from which to get the
  ///         information.
  ///     timeout (`float`, *optional*):
  ///         Whether to set a timeout for the request to the Hub.
  ///     files_metadata (`bool`, *optional*):
  ///         Whether or not to retrieve metadata for files in the repository
  ///         (size, LFS metadata, etc). Defaults to `False`.
  ///     expand (`List[ExpandDatasetProperty_T]`, *optional*):
  ///         List properties to return in the response. When used, only the properties in the list will be returned.
  ///         This parameter cannot be used if `files_metadata` is passed.
  ///         Possible values are `"author"`, `"cardData"`, `"citation"`, `"createdAt"`, `"disabled"`, `"description"`, `"downloads"`, `"downloadsAllTime"`, `"gated"`, `"lastModified"`, `"likes"`, `"paperswithcode_id"`, `"private"`, `"siblings"`, `"sha"`, `"tags"`, `"trendingScore"`,`"usedStorage"`, `"resourceGroup"` and `"xetEnabled"`.
  ///     token (Union[bool, str, None], optional):
  ///         A valid user access token (string). Defaults to the locally saved
  ///         token, which is the recommended method for authentication (see
  ///         https://huggingface.co/docs/huggingface_hub/quick-start#authentication).
  ///         To disable authentication, pass `False`.
  ///
  /// Returns:
  ///     [`hf_api.DatasetInfo`]: The dataset repository information.
  ///
  /// <Tip>
  ///
  /// Raises the following errors:
  ///
  ///     - [`~utils.RepositoryNotFoundError`]
  ///       If the repository to download from cannot be found. This may be because it doesn't exist,
  ///       or because it is set to `private` and you do not have access.
  ///     - [`~utils.RevisionNotFoundError`]
  ///       If the revision to download from cannot be found.
  ///
  /// </Tip>
  Future<DatasetInfo> datasetInfo(
    String repoId,
    {
      String? revision,
      double? timeout,
      bool filesMetadata = false,
      // List<ExpandDatasetProperty>? expand,
      List<ExpandProperty>? expand,
      dynamic token,
    }
  ) async {
    if (expand != null && filesMetadata) {
      throw ArgumentError('`expand` cannot be used if `files_metadata` is set.');
    }

    final headers = await _buildHfHeaders(token: token);
    final path = revision == null
        ? '$endpoint/api/datasets/$repoId'
        : '$endpoint/api/datasets/$repoId/revision/${Uri.encodeFull(revision).replaceAll('/', '%2F')}';
    final Map<String, dynamic> params = {};
    if (filesMetadata) {
      params['blobs'] = true;
    }
    if (expand != null) {
      params['expand'] = expand;
    }

    final (r, raiseForStatus) = await raiseForStatusDioWrapper(() async {
      return await getSession().get(
        path,
        queryParameters: params,
        options: Options(
          responseType: ResponseType.json,
          headers: headers,
          receiveTimeout: timeout != null ? Duration(milliseconds: (timeout * 1000).toInt()) : null,
        ),
      );
    });
    hfRaiseForStatus(r, raiseForStatus);
    return DatasetInfo.fromJson(r.data);
  }

  /// Get info on one specific Space on huggingface.co.
  ///
  /// Space can be private if you pass an acceptable token.
  ///
  /// Args:
  ///     repo_id (`str`):
  ///         A namespace (user or an organization) and a repo name separated
  ///         by a `/`.
  ///     revision (`str`, *optional*):
  ///         The revision of the space repository from which to get the
  ///         information.
  ///     timeout (`float`, *optional*):
  ///         Whether to set a timeout for the request to the Hub.
  ///     files_metadata (`bool`, *optional*):
  ///         Whether or not to retrieve metadata for files in the repository
  ///         (size, LFS metadata, etc). Defaults to `False`.
  ///     expand (`List[ExpandSpaceProperty_T]`, *optional*):
  ///         List properties to return in the response. When used, only the properties in the list will be returned.
  ///         This parameter cannot be used if `full` is passed.
  ///         Possible values are `"author"`, `"cardData"`, `"createdAt"`, `"datasets"`, `"disabled"`, `"lastModified"`, `"likes"`, `"models"`, `"private"`, `"runtime"`, `"sdk"`, `"siblings"`, `"sha"`, `"subdomain"`, `"tags"`, `"trendingScore"`, `"usedStorage"`, `"resourceGroup"` and `"xetEnabled"`.
  ///     token (Union[bool, str, None], optional):
  ///         A valid user access token (string). Defaults to the locally saved
  ///         token, which is the recommended method for authentication (see
  ///         https://huggingface.co/docs/huggingface_hub/quick-start#authentication).
  ///         To disable authentication, pass `False`.
  ///
  /// Returns:
  ///     [`~hf_api.SpaceInfo`]: The space repository information.
  ///
  /// <Tip>
  ///
  /// Raises the following errors:
  ///
  ///     - [`~utils.RepositoryNotFoundError`]
  ///       If the repository to download from cannot be found. This may be because it doesn't exist,
  ///       or because it is set to `private` and you do not have access.
  ///     - [`~utils.RevisionNotFoundError`]
  ///       If the revision to download from cannot be found.
  ///
  /// </Tip>
  Future<SpaceInfo> spaceInfo(
    String repoId,
    {
      String? revision,
      double? timeout,
      bool filesMetadata = false,
      // List<ExpandSpaceProperty>? expand,
      List<ExpandProperty>? expand,
      dynamic token,
    }
  ) async {
    if (expand != null && filesMetadata) {
      throw ArgumentError('`expand` cannot be used if `files_metadata` is set.');
    }

    final headers = await _buildHfHeaders(token: token);
    final path = revision == null
        ? '$endpoint/api/spaces/$repoId'
        : '$endpoint/api/spaces/$repoId/revision/${Uri.encodeFull(revision).replaceAll('/', '%2F')}';
    final Map<String, dynamic> params = {};
    if (filesMetadata) {
      params['blobs'] = true;
    }
    if (expand != null) {
      params['expand'] = expand;
    }

    final (r, raiseForStatus) = await raiseForStatusDioWrapper(() async {
      return await getSession().get(
        path,
        queryParameters: params,
        options: Options(
          responseType: ResponseType.json,
          headers: headers,
          receiveTimeout: timeout != null ? Duration(milliseconds: (timeout * 1000).toInt()) : null,
        ),
      );
    });
    hfRaiseForStatus(r, raiseForStatus);
    return SpaceInfo.fromJson(r.data);
  }

  /// Get the info object for a given repo of a given type.
  ///
  /// Args:
  ///     repo_id (`str`):
  ///         A namespace (user or an organization) and a repo name separated
  ///         by a `/`.
  ///     revision (`str`, *optional*):
  ///         The revision of the repository from which to get the
  ///         information.
  ///     repo_type (`str`, *optional*):
  ///         Set to `"dataset"` or `"space"` if getting repository info from a dataset or a space,
  ///         `None` or `"model"` if getting repository info from a model. Default is `None`.
  ///     timeout (`float`, *optional*):
  ///         Whether to set a timeout for the request to the Hub.
  ///     expand (`ExpandModelProperty_T` or `ExpandDatasetProperty_T` or `ExpandSpaceProperty_T`, *optional*):
  ///         List properties to return in the response. When used, only the properties in the list will be returned.
  ///         This parameter cannot be used if `files_metadata` is passed.
  ///         For an exhaustive list of available properties, check out [`model_info`], [`dataset_info`] or [`space_info`].
  ///     files_metadata (`bool`, *optional*):
  ///         Whether or not to retrieve metadata for files in the repository
  ///         (size, LFS metadata, etc). Defaults to `False`.
  ///     token (Union[bool, str, None], optional):
  ///         A valid user access token (string). Defaults to the locally saved
  ///         token, which is the recommended method for authentication (see
  ///         https://huggingface.co/docs/huggingface_hub/quick-start#authentication).
  ///         To disable authentication, pass `False`.
  ///
  /// Returns:
  ///     `Union[SpaceInfo, DatasetInfo, ModelInfo]`: The repository information, as a
  ///     [`huggingface_hub.hf_api.DatasetInfo`], [`huggingface_hub.hf_api.ModelInfo`]
  ///     or [`huggingface_hub.hf_api.SpaceInfo`] object.
  ///
  /// <Tip>
  ///
  /// Raises the following errors:
  ///
  ///     - [`~utils.RepositoryNotFoundError`]
  ///       If the repository to download from cannot be found. This may be because it doesn't exist,
  ///       or because it is set to `private` and you do not have access.
  ///     - [`~utils.RevisionNotFoundError`]
  ///       If the revision to download from cannot be found.
  ///
  /// </Tip>
  Future<RepoInfoBase> repoInfo({
    required String repoId,
    String? revision,
    String? repoType,
    double? timeout,
    bool filesMetadata = false,
    List<ExpandProperty>? expand,
    dynamic token,
  }) async {
    Future<RepoInfoBase> Function(String repoId, {
      String? revision,
      double? timeout,
      bool filesMetadata,
      List<ExpandProperty>? expand,
      dynamic token,
    }) method;
    if (repoType == null || repoType == 'model') {
      method = modelInfo;
    } else if (repoType == 'dataset') {
      method = datasetInfo;
    } else if (repoType == 'space') {
      method = spaceInfo;
    } else {
      throw ArgumentError('Unsupported repo type.');
    }
    return await method(
      repoId,
      revision: revision,
      token: token,
      timeout: timeout,
      expand: expand,
      filesMetadata: filesMetadata,
    );
  }

  /// List a repo tree's files and folders and get information about them.
  ///
  /// Args:
  ///     repo_id (`str`):
  ///         A namespace (user or an organization) and a repo name separated by a `/`.
  ///     path_in_repo (`str`, *optional*):
  ///         Relative path of the tree (folder) in the repo, for example:
  ///         `"checkpoints/1fec34a/results"`. Will default to the root tree (folder) of the repository.
  ///     recursive (`bool`, *optional*, defaults to `False`):
  ///         Whether to list tree's files and folders recursively.
  ///     expand (`bool`, *optional*, defaults to `False`):
  ///         Whether to fetch more information about the tree's files and folders (e.g. last commit and files' security scan results). This
  ///         operation is more expensive for the server so only 50 results are returned per page (instead of 1000).
  ///         As pagination is implemented in `huggingface_hub`, this is transparent for you except for the time it
  ///         takes to get the results.
  ///     revision (`str`, *optional*):
  ///         The revision of the repository from which to get the tree. Defaults to `"main"` branch.
  ///     repo_type (`str`, *optional*):
  ///         The type of the repository from which to get the tree (`"model"`, `"dataset"` or `"space"`.
  ///         Defaults to `"model"`.
  ///     token (Union[bool, str, None], optional):
  ///         A valid user access token (string). Defaults to the locally saved
  ///         token, which is the recommended method for authentication (see
  ///         https://huggingface.co/docs/huggingface_hub/quick-start#authentication).
  ///         To disable authentication, pass `False`.
  ///
  /// Returns:
  ///     `Iterable[Union[RepoFile, RepoFolder]]`:
  ///         The information about the tree's files and folders, as an iterable of [`RepoFile`] and [`RepoFolder`] objects. The order of the files and folders is
  ///         not guaranteed.
  ///
  /// Raises:
  ///     [`~utils.RepositoryNotFoundError`]:
  ///         If repository is not found (error 404): wrong repo_id/repo_type, private but not authenticated or repo
  ///         does not exist.
  ///     [`~utils.RevisionNotFoundError`]:
  ///         If revision is not found (error 404) on the repo.
  ///     [`~utils.EntryNotFoundError`]:
  ///         If the tree (folder) does not exist (error 404) on the repo.
  ///
  /// Examples:
  ///
  ///     Get information about a repo's tree.
  ///     ```py
  ///     >>> from huggingface_hub import list_repo_tree
  ///     >>> repo_tree = list_repo_tree("lysandre/arxiv-nlp")
  ///     >>> repo_tree
  ///     <generator object HfApi.list_repo_tree at 0x7fa4088e1ac0>
  ///     >>> list(repo_tree)
  ///     [
  ///         RepoFile(path='.gitattributes', size=391, blob_id='ae8c63daedbd4206d7d40126955d4e6ab1c80f8f', lfs=None, last_commit=None, security=None),
  ///         RepoFile(path='README.md', size=391, blob_id='43bd404b159de6fba7c2f4d3264347668d43af25', lfs=None, last_commit=None, security=None),
  ///         RepoFile(path='config.json', size=554, blob_id='2f9618c3a19b9a61add74f70bfb121335aeef666', lfs=None, last_commit=None, security=None),
  ///         RepoFile(
  ///             path='flax_model.msgpack', size=497764107, blob_id='8095a62ccb4d806da7666fcda07467e2d150218e',
  ///             lfs={'size': 497764107, 'sha256': 'd88b0d6a6ff9c3f8151f9d3228f57092aaea997f09af009eefd7373a77b5abb9', 'pointer_size': 134}, last_commit=None, security=None
  ///         ),
  ///         RepoFile(path='merges.txt', size=456318, blob_id='226b0752cac7789c48f0cb3ec53eda48b7be36cc', lfs=None, last_commit=None, security=None),
  ///         RepoFile(
  ///             path='pytorch_model.bin', size=548123560, blob_id='64eaa9c526867e404b68f2c5d66fd78e27026523',
  ///             lfs={'size': 548123560, 'sha256': '9be78edb5b928eba33aa88f431551348f7466ba9f5ef3daf1d552398722a5436', 'pointer_size': 134}, last_commit=None, security=None
  ///         ),
  ///         RepoFile(path='vocab.json', size=898669, blob_id='b00361fece0387ca34b4b8b8539ed830d644dbeb', lfs=None, last_commit=None, security=None)]
  ///     ]
  ///     ```
  ///
  ///     Get even more information about a repo's tree (last commit and files' security scan results)
  ///     ```py
  ///     >>> from huggingface_hub import list_repo_tree
  ///     >>> repo_tree = list_repo_tree("prompthero/openjourney-v4", expand=True)
  ///     >>> list(repo_tree)
  ///     [
  ///         RepoFolder(
  ///             path='feature_extractor',
  ///             tree_id='aa536c4ea18073388b5b0bc791057a7296a00398',
  ///             last_commit={
  ///                 'oid': '47b62b20b20e06b9de610e840282b7e6c3d51190',
  ///                 'title': 'Upload diffusers weights (#48)',
  ///                 'date': datetime.datetime(2023, 3, 21, 9, 5, 27, tzinfo=datetime.timezone.utc)
  ///             }
  ///         ),
  ///         RepoFolder(
  ///             path='safety_checker',
  ///             tree_id='65aef9d787e5557373fdf714d6c34d4fcdd70440',
  ///             last_commit={
  ///                 'oid': '47b62b20b20e06b9de610e840282b7e6c3d51190',
  ///                 'title': 'Upload diffusers weights (#48)',
  ///                 'date': datetime.datetime(2023, 3, 21, 9, 5, 27, tzinfo=datetime.timezone.utc)
  ///             }
  ///         ),
  ///         RepoFile(
  ///             path='model_index.json',
  ///             size=582,
  ///             blob_id='d3d7c1e8c3e78eeb1640b8e2041ee256e24c9ee1',
  ///             lfs=None,
  ///             last_commit={
  ///                 'oid': 'b195ed2d503f3eb29637050a886d77bd81d35f0e',
  ///                 'title': 'Fix deprecation warning by changing `CLIPFeatureExtractor` to `CLIPImageProcessor`. (#54)',
  ///                 'date': datetime.datetime(2023, 5, 15, 21, 41, 59, tzinfo=datetime.timezone.utc)
  ///             },
  ///             security={
  ///                 'safe': True,
  ///                 'av_scan': {'virusFound': False, 'virusNames': None},
  ///                 'pickle_import_scan': None
  ///             }
  ///         )
  ///         ...
  ///     ]
  ///     ```
  Stream<RepoFileOrFolder> listRepoTree({
    required String repoId,
    String? pathInRepo,
    bool recursive = false,
    bool expand = false,
    String? revision,
    String? repoType,
    dynamic token,
  }) async* {
    repoType ??= constants.REPO_TYPE_MODEL;
    revision = revision != null ? Uri.encodeFull(revision).replaceAll('/', '%2F') : constants.DEFAULT_REVISION;
    final headers = await _buildHfHeaders(token: token);

    final encodedPathInRepo = pathInRepo != null ? '/${Uri.encodeFull(pathInRepo).replaceAll('/', '%2F')}' : '';
    final treeUrl = '$endpoint/api/${repoType}s/$repoId/tree$revision$encodedPathInRepo';
    await for (final pathInfo in paginate(path: treeUrl, headers: headers, params: {'recursive': recursive, 'expand': expand})) {
      yield pathInfo['type'] == 'file' ? RepoFile.fromJson(pathInfo) : RepoFolder.fromJson(pathInfo);
    }
  }

  // #############
  // # Internals #
  // #############

  /// Alias for [buildHfHeaders] that uses the token from [HfApi] client
  /// when [token] is not provided.
  Future<Map<String, String>> _buildHfHeaders({
    dynamic token,
    String? libraryName,
    String? libraryVersion,
    dynamic userAgent,
    Map<String, String>? headers,
  }) => buildHfHeaders(
    // Cannot do `token = token or self.token` as token can be `False`.
    // But in dart we can :)
    token: token ?? this.token,
    libraryName: libraryName ?? this.libraryName,
    libraryVersion: libraryVersion ?? this.libraryVersion,
    userAgent: userAgent ?? this.userAgent,
    headers: headers,
  );
}
