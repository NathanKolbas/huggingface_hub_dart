/// Flattened representation of individual evaluation results found in model-index of Model Cards.
///
/// For more information on the model-index spec, see https://github.com/huggingface/hub-docs/blob/main/modelcard.md?plain=1.
///
/// Args:
///     task_type (`str`):
///         The task identifier. Example: "image-classification".
///     dataset_type (`str`):
///         The dataset identifier. Example: "common_voice". Use dataset id from https://hf.co/datasets.
///     dataset_name (`str`):
///         A pretty name for the dataset. Example: "Common Voice (French)".
///     metric_type (`str`):
///         The metric identifier. Example: "wer". Use metric id from https://hf.co/metrics.
///     metric_value (`Any`):
///         The metric value. Example: 0.9 or "20.0 ± 1.2".
///     task_name (`str`, *optional*):
///         A pretty name for the task. Example: "Speech Recognition".
///     dataset_config (`str`, *optional*):
///         The name of the dataset configuration used in `load_dataset()`.
///         Example: fr in `load_dataset("common_voice", "fr")`. See the `datasets` docs for more info:
///         https://hf.co/docs/datasets/package_reference/loading_methods#datasets.load_dataset.name
///     dataset_split (`str`, *optional*):
///         The split used in `load_dataset()`. Example: "test".
///     dataset_revision (`str`, *optional*):
///         The revision (AKA Git Sha) of the dataset used in `load_dataset()`.
///         Example: 5503434ddd753f426f4b38109466949a1217c2bb
///     dataset_args (`Dict[str, Any]`, *optional*):
///         The arguments passed during `Metric.compute()`. Example for `bleu`: `{"max_order": 4}`
///     metric_name (`str`, *optional*):
///         A pretty name for the metric. Example: "Test WER".
///     metric_config (`str`, *optional*):
///         The name of the metric configuration used in `load_metric()`.
///         Example: bleurt-large-512 in `load_metric("bleurt", "bleurt-large-512")`.
///         See the `datasets` docs for more info: https://huggingface.co/docs/datasets/v2.1.0/en/loading#load-configurations
///     metric_args (`Dict[str, Any]`, *optional*):
///         The arguments passed during `Metric.compute()`. Example for `bleu`: max_order: 4
///     verified (`bool`, *optional*):
///         Indicates whether the metrics originate from Hugging Face's [evaluation service](https://huggingface.co/spaces/autoevaluate/model-evaluator) or not. Automatically computed by Hugging Face, do not set.
///     verify_token (`str`, *optional*):
///         A JSON Web Token that is used to verify whether the metrics originate from Hugging Face's [evaluation service](https://huggingface.co/spaces/autoevaluate/model-evaluator) or not.
///     source_name (`str`, *optional*):
///         The name of the source of the evaluation result. Example: "Open LLM Leaderboard".
///     source_url (`str`, *optional*):
///         The URL of the source of the evaluation result. Example: "https://huggingface.co/spaces/open-llm-leaderboard/open_llm_leaderboard".
// @dataclass
class EvalResult {
  // Required

  /// The task identifier
  /// Example: automatic-speech-recognition
  String taskType;

  /// The dataset identifier
  /// Example: common_voice. Use dataset id from https://hf.co/datasets
  String datasetType;

  /// A pretty name for the dataset.
  /// Example: Common Voice (French)
  String datasetName;

  /// The metric identifier
  /// Example: wer. Use metric id from https://hf.co/metrics
  String metricType;

  /// Value of the metric.
  /// Example: 20.0 or "20.0 ± 1.2"
  dynamic metricValue;

  // Optional

  /// A pretty name for the task.
  /// Example: Speech Recognition
  String? taskName;

  /// The name of the dataset configuration used in `load_dataset()`.
  /// Example: fr in `load_dataset("common_voice", "fr")`.
  /// See the `datasets` docs for more info:
  /// https://huggingface.co/docs/datasets/package_reference/loading_methods#datasets.load_dataset.name
  String? datasetConfig;

  /// The split used in `load_dataset()`.
  /// Example: test
  String? datasetSplit;

  /// The revision (AKA Git Sha) of the dataset used in `load_dataset()`.
  /// Example: 5503434ddd753f426f4b38109466949a1217c2bb
  String? datasetRevision;

  /// The arguments passed during `Metric.compute()`.
  /// Example for `bleu`: max_order: 4
  Map<String, dynamic>? datasetArgs;

  /// A pretty name for the metric.
  /// Example: Test WER
  String? metricName;

  /// The name of the metric configuration used in `load_metric()`.
  /// Example: bleurt-large-512 in `load_metric("bleurt", "bleurt-large-512")`.
  /// See the `datasets` docs for more info: https://huggingface.co/docs/datasets/v2.1.0/en/loading#load-configurations
  String? metricConfig;

  /// The arguments passed during `Metric.compute()`.
  /// Example for `bleu`: max_order: 4
  Map<String, dynamic>? metricArgs;

  /// Indicates whether the metrics originate from Hugging Face's [evaluation service](https://huggingface.co/spaces/autoevaluate/model-evaluator) or not. Automatically computed by Hugging Face, do not set.
  bool? verified;

  /// A JSON Web Token that is used to verify whether the metrics originate from Hugging Face's [evaluation service](https://huggingface.co/spaces/autoevaluate/model-evaluator) or not.
  String? verifyToken;

  /// The name of the source of the evaluation result.
  /// Example: Open LLM Leaderboard
  String? sourceName;

  /// The URL of the source of the evaluation result.
  /// Example: https://huggingface.co/spaces/open-llm-leaderboard/open_llm_leaderboard
  String? sourceUrl;

  EvalResult({
    required this.taskType,
    required this.datasetType,
    required this.datasetName,
    required this.metricType,
    this.metricValue,
    this.taskName,
    this.datasetConfig,
    this.datasetSplit,
    this.datasetRevision,
    this.datasetArgs,
    this.metricName,
    this.metricConfig,
    this.metricArgs,
    this.verified,
    this.verifyToken,
    this.sourceName,
    this.sourceUrl,
  });
}

/// Structure containing metadata from a RepoCard.
///
/// [`CardData`] is the parent class of [`ModelCardData`] and [`DatasetCardData`].
///
/// Metadata can be exported as a dictionary or YAML. Export can be customized to alter the representation of the data
/// (example: flatten evaluation results). `CardData` behaves as a dictionary (can get, pop, set values) but do not
/// inherit from `dict` to allow this export step.
// @dataclass
class CardData {

}

List<EvalResult> _validateEvalResults(List<EvalResult>? evalResults, String? modelName) {
  if (evalResults == null) return [];
  if (modelName == null) {
    throw ArgumentError('Passing `eval_results` requires `model_name` to be set.');
  }
  return evalResults;
}

/// Model Card Metadata that is used by Hugging Face Hub when included at the top of your README.md
///
/// Args:
///     base_model (`str` or `List[str]`, *optional*):
///         The identifier of the base model from which the model derives. This is applicable for example if your model is a
///         fine-tune or adapter of an existing model. The value must be the ID of a model on the Hub (or a list of IDs
///         if your model derives from multiple models). Defaults to None.
///     datasets (`Union[str, List[str]]`, *optional*):
///         Dataset or list of datasets that were used to train this model. Should be a dataset ID
///         found on https://hf.co/datasets. Defaults to None.
///     eval_results (`Union[List[EvalResult], EvalResult]`, *optional*):
///         List of `huggingface_hub.EvalResult` that define evaluation results of the model. If provided,
///         `model_name` is used to as a name on PapersWithCode's leaderboards. Defaults to `None`.
///     language (`Union[str, List[str]]`, *optional*):
///         Language of model's training data or metadata. It must be an ISO 639-1, 639-2 or
///         639-3 code (two/three letters), or a special value like "code", "multilingual". Defaults to `None`.
///     library_name (`str`, *optional*):
///         Name of library used by this model. Example: keras or any library from
///         https://github.com/huggingface/huggingface.js/blob/main/packages/tasks/src/model-libraries.ts.
///         Defaults to None.
///     license (`str`, *optional*):
///         License of this model. Example: apache-2.0 or any license from
///         https://huggingface.co/docs/hub/repositories-licenses. Defaults to None.
///     license_name (`str`, *optional*):
///         Name of the license of this model. Defaults to None. To be used in conjunction with `license_link`.
///         Common licenses (Apache-2.0, MIT, CC-BY-SA-4.0) do not need a name. In that case, use `license` instead.
///     license_link (`str`, *optional*):
///         Link to the license of this model. Defaults to None. To be used in conjunction with `license_name`.
///         Common licenses (Apache-2.0, MIT, CC-BY-SA-4.0) do not need a link. In that case, use `license` instead.
///     metrics (`List[str]`, *optional*):
///         List of metrics used to evaluate this model. Should be a metric name that can be found
///         at https://hf.co/metrics. Example: 'accuracy'. Defaults to None.
///     model_name (`str`, *optional*):
///         A name for this model. It is used along with
///         `eval_results` to construct the `model-index` within the card's metadata. The name
///         you supply here is what will be used on PapersWithCode's leaderboards. If None is provided
///         then the repo name is used as a default. Defaults to None.
///     pipeline_tag (`str`, *optional*):
///         The pipeline tag associated with the model. Example: "text-classification".
///     tags (`List[str]`, *optional*):
///         List of tags to add to your model that can be used when filtering on the Hugging
///         Face Hub. Defaults to None.
///     ignore_metadata_errors (`str`):
///         If True, errors while parsing the metadata section will be ignored. Some information might be lost during
///         the process. Use it at your own risk.
///     kwargs (`dict`, *optional*):
///         Additional metadata that will be added to the model card. Defaults to None.
///
/// Example:
///     ```python
///     >>> from huggingface_hub import ModelCardData
///     >>> card_data = ModelCardData(
///     ...     language="en",
///     ...     license="mit",
///     ...     library_name="timm",
///     ...     tags=['image-classification', 'resnet'],
///     ... )
///     >>> card_data.to_dict()
///     {'language': 'en', 'license': 'mit', 'library_name': 'timm', 'tags': ['image-classification', 'resnet']}
///
///     ```
class ModelCardData extends CardData {
  late List<String>? baseModel;
  late List<String>? datasets;
  late List<EvalResult>? evalResults;
  late List<String>? language;
  late String? libraryName;
  late String? license;
  late String? licenseName;
  late String? licenseLink;
  late List<String>? metrics;
  late String? modelName;
  late String? pipelineTag;
  late List<String>? tags;

  ModelCardData({
    this.baseModel,
    this.datasets,
    this.evalResults,
    this.language,
    this.libraryName,
    this.license,
    this.licenseName,
    this.licenseLink,
    this.metrics,
    this.modelName,
    this.pipelineTag,
    this.tags,
    bool ignoreMetadataErrors = false,
    Map<String, dynamic>? kwargs,
  }) {
    kwargs ??= {};
    tags = tags?.toSet().toList();

    final modelIndex = kwargs.remove('model-index');
    if (modelIndex != null || modelIndex == true) {
      try {
        final (modelName, evalResults) = modelIndexToEvalResults(modelIndex);
        this.modelName = modelName;
        this.evalResults = evalResults;
      } catch (e) {
        if (ignoreMetadataErrors) {
          print('Invalid model-index. Not loading eval results into CardData.');
        } else {
          throw ArgumentError(
              'Invalid `model_index` in metadata cannot be parsed: ${e.runtimeType} $e. Pass'
              ' `ignore_metadata_errors=True` to ignore this error while loading a Model Card. Warning:'
              ' some information will be lost. Use it at your own risk.'
          );
        }
      }
    }

    if (evalResults != null) {
      try {
        evalResults = _validateEvalResults(evalResults, modelName);
      } catch (e) {
        if (ignoreMetadataErrors) {
          print('Failed to validate eval_results: $e. Not loading eval results into CardData.');
        } else {
          throw ArgumentError('Failed to validate eval_results: $e');
        }
      }
    }
  }

  factory ModelCardData.fromJson(Map<String, dynamic> data, {bool ignoreMetadataErrors = false}) => ModelCardData(
    baseModel: data['base_model'],
    datasets: data['datasets'],
    evalResults: data['eval_results'],
    language: data['language'],
    libraryName: data['library_name'],
    license: data['license'],
    licenseName: data['license_name'],
    licenseLink: data['license_link'],
    metrics: data['metrics'],
    modelName: data['model_name'],
    pipelineTag: data['pipeline_tag'],
    tags: data['tags'],
    ignoreMetadataErrors: ignoreMetadataErrors,
    kwargs: data,
  );
}

/// Dataset Card Metadata that is used by Hugging Face Hub when included at the top of your README.md
///
/// Args:
///     language (`List[str]`, *optional*):
///         Language of dataset's data or metadata. It must be an ISO 639-1, 639-2 or
///         639-3 code (two/three letters), or a special value like "code", "multilingual".
///     license (`Union[str, List[str]]`, *optional*):
///         License(s) of this dataset. Example: apache-2.0 or any license from
///         https://huggingface.co/docs/hub/repositories-licenses.
///     annotations_creators (`Union[str, List[str]]`, *optional*):
///         How the annotations for the dataset were created.
///         Options are: 'found', 'crowdsourced', 'expert-generated', 'machine-generated', 'no-annotation', 'other'.
///     language_creators (`Union[str, List[str]]`, *optional*):
///         How the text-based data in the dataset was created.
///         Options are: 'found', 'crowdsourced', 'expert-generated', 'machine-generated', 'other'
///     multilinguality (`Union[str, List[str]]`, *optional*):
///         Whether the dataset is multilingual.
///         Options are: 'monolingual', 'multilingual', 'translation', 'other'.
///     size_categories (`Union[str, List[str]]`, *optional*):
///         The number of examples in the dataset. Options are: 'n<1K', '1K<n<10K', '10K<n<100K',
///         '100K<n<1M', '1M<n<10M', '10M<n<100M', '100M<n<1B', '1B<n<10B', '10B<n<100B', '100B<n<1T', 'n>1T', and 'other'.
///     source_datasets (`List[str]]`, *optional*):
///         Indicates whether the dataset is an original dataset or extended from another existing dataset.
///         Options are: 'original' and 'extended'.
///     task_categories (`Union[str, List[str]]`, *optional*):
///         What categories of task does the dataset support?
///     task_ids (`Union[str, List[str]]`, *optional*):
///         What specific tasks does the dataset support?
///     paperswithcode_id (`str`, *optional*):
///         ID of the dataset on PapersWithCode.
///     pretty_name (`str`, *optional*):
///         A more human-readable name for the dataset. (ex. "Cats vs. Dogs")
///     train_eval_index (`Dict`, *optional*):
///         A dictionary that describes the necessary spec for doing evaluation on the Hub.
///         If not provided, it will be gathered from the 'train-eval-index' key of the kwargs.
///     config_names (`Union[str, List[str]]`, *optional*):
///         A list of the available dataset configs for the dataset.
class DatasetCardData extends CardData {
  List<String>? language;
  List<String>? license;
  List<String>? annotationsCreators;
  List<String>? languageCreators;
  List<String>? multilinguality;
  List<String>? sizeCategories;
  List<String>? sourceDatasets;
  List<String>? taskCategories;
  List<String>? taskIds;
  String? paperswithcodeId;
  String? prettyName;
  Map<String, dynamic>? trainEvalIndex;
  List<String>? configNames;

  DatasetCardData({
    this.language,
    this.license,
    this.annotationsCreators,
    this.languageCreators,
    this.multilinguality,
    this.sizeCategories,
    this.sourceDatasets,
    this.taskCategories,
    this.taskIds,
    this.paperswithcodeId,
    this.prettyName,
    this.trainEvalIndex,
    this.configNames,
    bool ignoreMetadataErrors = false,
    Map<String, dynamic>? kwargs,
  }) {
    kwargs ??= {};

    // TODO - maybe handle this similarly to EvalResult?
    trainEvalIndex ??= kwargs.remove('train-eval-index');
  }

  factory DatasetCardData.fromJson(Map<String, dynamic> data, {bool ignoreMetadataErrors = false}) => DatasetCardData(
    language: data['language'],
    license: data['license'],
    annotationsCreators: data['annotations_creators'],
    languageCreators: data['language_creators'],
    multilinguality: data['multilinguality'],
    sizeCategories: data['size_categories'],
    sourceDatasets: data['source_datasets'],
    taskCategories: data['task_categories'],
    taskIds: data['task_ids'],
    paperswithcodeId: data['paperswithcode_id'],
    prettyName: data['pretty_name'],
    trainEvalIndex: data['train_eval_index'],
    configNames: data['config_names'],
    ignoreMetadataErrors: ignoreMetadataErrors,
    kwargs: data,
  );
}

/// Space Card Metadata that is used by Hugging Face Hub when included at the top of your README.md
///
/// To get an exhaustive reference of Spaces configuration, please visit https://huggingface.co/docs/hub/spaces-config-reference#spaces-configuration-reference.
///
/// Args:
///     title (`str`, *optional*)
///         Title of the Space.
///     sdk (`str`, *optional*)
///         SDK of the Space (one of `gradio`, `streamlit`, `docker`, or `static`).
///     sdk_version (`str`, *optional*)
///         Version of the used SDK (if Gradio/Streamlit sdk).
///     python_version (`str`, *optional*)
///         Python version used in the Space (if Gradio/Streamlit sdk).
///     app_file (`str`, *optional*)
///         Path to your main application file (which contains either gradio or streamlit Python code, or static html code).
///         Path is relative to the root of the repository.
///     app_port (`str`, *optional*)
///         Port on which your application is running. Used only if sdk is `docker`.
///     license (`str`, *optional*)
///         License of this model. Example: apache-2.0 or any license from
///         https://huggingface.co/docs/hub/repositories-licenses.
///     duplicated_from (`str`, *optional*)
///         ID of the original Space if this is a duplicated Space.
///     models (List[`str`], *optional*)
///         List of models related to this Space. Should be a dataset ID found on https://hf.co/models.
///     datasets (`List[str]`, *optional*)
///         List of datasets related to this Space. Should be a dataset ID found on https://hf.co/datasets.
///     tags (`List[str]`, *optional*)
///         List of tags to add to your Space that can be used when filtering on the Hub.
///     ignore_metadata_errors (`str`):
///         If True, errors while parsing the metadata section will be ignored. Some information might be lost during
///         the process. Use it at your own risk.
///     kwargs (`dict`, *optional*):
///         Additional metadata that will be added to the space card.
///
/// Example:
///     ```python
///     >>> from huggingface_hub import SpaceCardData
///     >>> card_data = SpaceCardData(
///     ...     title="Dreambooth Training",
///     ...     license="mit",
///     ...     sdk="gradio",
///     ...     duplicated_from="multimodalart/dreambooth-training"
///     ... )
///     >>> card_data.to_dict()
///     {'title': 'Dreambooth Training', 'sdk': 'gradio', 'license': 'mit', 'duplicated_from': 'multimodalart/dreambooth-training'}
///     ```
class SpaceCardData extends CardData {
  String? title;
  String? sdk;
  String? sdkVersion;
  String? pythonVersion;
  String? appFile;
  String? appPort;
  String? license;
  String? duplicatedFrom;
  List<String>? models;
  List<String>? datasets;
  List<String>? tags;

  SpaceCardData({
    this.title,
    this.sdk,
    this.sdkVersion,
    this.pythonVersion,
    this.appFile,
    this.appPort,
    this.license,
    this.duplicatedFrom,
    this.models,
    this.datasets,
    this.tags,
    bool ignoreMetadataErrors = false,
    Map<String, dynamic>? kwargs,
  }) {
    kwargs ??= {};

    tags = tags?.toSet().toList();
  }

  factory SpaceCardData.fromJson(Map<String, dynamic> data, {bool ignoreMetadataErrors = false}) => SpaceCardData(
    title: data['title'],
    sdk: data['sdk'],
    sdkVersion: data['sdk_version'],
    pythonVersion: data['python_version'],
    appFile: data['app_file'],
    appPort: data['app_port'],
    license: data['license'],
    duplicatedFrom: data['duplicated_from'],
    models: data['models'],
    datasets: data['datasets'],
    tags: data['tags'],
    ignoreMetadataErrors: ignoreMetadataErrors,
    kwargs: data,
  );
}

/// Takes in a model index and returns the model name and a list of `huggingface_hub.EvalResult` objects.
///
/// A detailed spec of the model index can be found here:
/// https://github.com/huggingface/hub-docs/blob/main/modelcard.md?plain=1
///
/// Args:
///     model_index (`List[Dict[str, Any]]`):
///         A model index data structure, likely coming from a README.md file on the
///         Hugging Face Hub.
///
/// Returns:
///     model_name (`str`):
///         The name of the model as found in the model index. This is used as the
///         identifier for the model on leaderboards like PapersWithCode.
///     eval_results (`List[EvalResult]`):
///         A list of `huggingface_hub.EvalResult` objects containing the metrics
///         reported in the provided model_index.
///
/// Example:
///     ```python
///     >>> from huggingface_hub.repocard_data import model_index_to_eval_results
///     >>> # Define a minimal model index
///     >>> model_index = [
///     ...     {
///     ...         "name": "my-cool-model",
///     ...         "results": [
///     ...             {
///     ...                 "task": {
///     ...                     "type": "image-classification"
///     ...                 },
///     ...                 "dataset": {
///     ...                     "type": "beans",
///     ...                     "name": "Beans"
///     ...                 },
///     ...                 "metrics": [
///     ...                     {
///     ...                         "type": "accuracy",
///     ...                         "value": 0.9
///     ...                     }
///     ...                 ]
///     ...             }
///     ...         ]
///     ...     }
///     ... ]
///     >>> model_name, eval_results = model_index_to_eval_results(model_index)
///     >>> model_name
///     'my-cool-model'
///     >>> eval_results[0].task_type
///     'image-classification'
///     >>> eval_results[0].metric_type
///     'accuracy'
///
///     ```
(String, List<EvalResult>) modelIndexToEvalResults(List<Map<String, dynamic>> modelIndex) {
  final List<EvalResult> evalResults = [];
  String? name;
  for (final elem in modelIndex) {
    name = elem['name'];
    final results = elem['results'];
    for (final result in results) {
      final taskType = result["task"]["type"];
      final taskName = result["task"]['name'];
      final datasetType = result["dataset"]["type"];
      final datasetName = result["dataset"]["name"];
      final datasetConfig = result["dataset"]['config'];
      final datasetSplit = result["dataset"]['split'];
      final datasetRevision = result["dataset"]['revision'];
      final datasetArgs = result["dataset"]['args'];
      final sourceName = (result['source'] ?? {})['name'];
      final sourceUrl = (result['source'] ?? {})['url'];

      for (final metric in result['metrics']) {
        final metricType = metric["type"];
        final metricValue = metric["value"];
        final metricName = metric['name'];
        final metricArgs = metric['args'];
        final metricConfig = metric['config'];
        final verified = metric['verified'];
        final verifyToken = metric['verifyToken'];

        final evalResult = EvalResult(
          taskType: taskType,
          datasetType: datasetType,
          datasetName: datasetName,
          metricType: metricType,
          metricValue: metricValue,
          taskName: taskName,
          datasetConfig: datasetConfig,
          datasetSplit: datasetSplit,
          datasetRevision: datasetRevision,
          datasetArgs: datasetArgs,
          metricName: metricName,
          metricArgs: metricArgs,
          metricConfig: metricConfig,
          verified: verified,
          verifyToken: verifyToken,
          sourceName: sourceName,
          sourceUrl: sourceUrl,
        );
        evalResults.add(evalResult);
      }
    }
  }
  return (name!, evalResults);
}
