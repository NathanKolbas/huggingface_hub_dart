/// Enumeration of possible stage of a Space on the Hub.
///
/// Value can be compared to a string:
/// ```py
/// assert SpaceStage.BUILDING == "BUILDING"
/// ```
///
/// Taken from https://github.com/huggingface/moon-landing/blob/main/server/repo_types/SpaceInfo.ts#L61 (private url).
enum SpaceStage {
  // Copied from moon-landing > server > repo_types > SpaceInfo.ts (private repo)
  NO_APP_FILE,
  CONFIG_ERROR,
  BUILDING,
  BUILD_ERROR,
  RUNNING,
  RUNNING_BUILDING,
  RUNTIME_ERROR,
  DELETING,
  STOPPED,
  PAUSED;

  String toJson() => name;

  factory SpaceStage.fromJson(String value) => values.byName(value);
}

/// Enumeration of hardwares available to run your Space on the Hub.
///
/// Value can be compared to a string:
/// ```py
/// assert SpaceHardware.CPU_BASIC == "cpu-basic"
/// ```
///
/// Taken from https://github.com/huggingface-internal/moon-landing/blob/main/server/repo_types/SpaceHardwareFlavor.ts (private url).
enum SpaceHardware {
  // CPU
  CPU_BASIC("cpu-basic"),
  CPU_UPGRADE("cpu-upgrade"),
  CPU_XL("cpu-xl"),

  // ZeroGPU
  ZERO_A10G("zero-a10g"),

  // GPU
  T4_SMALL("t4-small"),
  T4_MEDIUM("t4-medium"),
  L4X1("l4x1"),
  L4X4("l4x4"),
  L40SX1("l40sx1"),
  L40SX4("l40sx4"),
  L40SX8("l40sx8"),
  A10G_SMALL("a10g-small"),
  A10G_LARGE("a10g-large"),
  A10G_LARGEX2("a10g-largex2"),
  A10G_LARGEX4("a10g-largex4"),
  A100_LARGE("a100-large"),
  H100("h100"),
  H100X8("h100x8");

  final String value;

  const SpaceHardware(this.value);

  String toJson() => value;

  factory SpaceHardware.fromJson(String value) => values.firstWhere((e) => e.value == value);
}

/// Enumeration of persistent storage available for your Space on the Hub.
///
/// Value can be compared to a string:
/// ```py
/// assert SpaceStorage.SMALL == "small"
/// ```
///
/// Taken from https://github.com/huggingface/moon-landing/blob/main/server/repo_types/SpaceHardwareFlavor.ts#L24 (private url).
enum SpaceStorage {
  SMALL("small"),
  MEDIUM("medium"),
  LARGE("large");

  final String value;

  const SpaceStorage(this.value);

  String toJson() => value;

  factory SpaceStorage.fromJson(String value) => values.firstWhere((e) => e.value == value);
}

/// Contains information about the current runtime of a Space.
///
/// Args:
///     stage (`str`):
///         Current stage of the space. Example: RUNNING.
///     hardware (`str` or `None`):
///         Current hardware of the space. Example: "cpu-basic". Can be `None` if Space
///         is `BUILDING` for the first time.
///     requested_hardware (`str` or `None`):
///         Requested hardware. Can be different than `hardware` especially if the request
///         has just been made. Example: "t4-medium". Can be `None` if no hardware has
///         been requested yet.
///     sleep_time (`int` or `None`):
///         Number of seconds the Space will be kept alive after the last request. By default (if value is `None`), the
///         Space will never go to sleep if it's running on an upgraded hardware, while it will go to sleep after 48
///         hours on a free 'cpu-basic' hardware. For more details, see https://huggingface.co/docs/hub/spaces-gpus#sleep-time.
///     raw (`dict`):
///         Raw response from the server. Contains more information about the Space
///         runtime like number of replicas, number of cpu, memory size,...
// @dataclass
class SpaceRuntime {
  SpaceStage stage;
  SpaceHardware? hardware;
  SpaceHardware? requestedHardware;
  int? sleepTime;
  SpaceStorage? storage;
  Map raw;

  SpaceRuntime({
    required this.stage,
    this.hardware,
    this.requestedHardware,
    this.sleepTime,
    this.storage,
    required this.raw,
  });

  factory SpaceRuntime.fromJson(Map<String, dynamic> data) => SpaceRuntime(
    stage: SpaceStage.fromJson(data['stage']),
    hardware: SpaceHardware.fromJson((data['hardware'] ?? {})['current']),
    requestedHardware: SpaceHardware.fromJson((data['hardware'] ?? {})['requested']),
    sleepTime: data['gcTimeout'],
    storage: SpaceStorage.fromJson(data['storage']),
    raw: data,
  );
}
