import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;

/// The [SharedPreferences] key under which saved jobs are stored.
const jobsKey = 'ap_python_launcher_jobs';

/// A persisted record of a running launch job.
class SavedJob {
  /// Creates a [SavedJob] with the given [launchId], [repo], and [tag].
  SavedJob({required this.launchId, required this.repo, required this.tag});

  /// Deserializes a [SavedJob] from a JSON map.
  factory SavedJob.fromJson(Map<String, dynamic> json) {
    return SavedJob(
      launchId: (json['launchId'] as String?) ?? '',
      repo: (json['repo'] as String?) ?? '',
      tag: (json['tag'] as String?) ?? '',
    );
  }

  /// The unique identifier of the launch job.
  final String launchId;

  /// The repository associated with this job.
  final String repo;

  /// The image tag used for this job.
  final String tag;

  /// Serializes this [SavedJob] to a JSON map.
  Map<String, dynamic> toJson() => {
    'launchId': launchId,
    'repo': repo,
    'tag': tag,
  };
}

/// Persists and retrieves saved launch jobs using [SharedPreferences].
class JobStore {
  /// Returns all currently saved jobs, filtering out any malformed entries.
  Future<List<SavedJob>> loadJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(jobsKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedJob.fromJson)
          .where(
            (j) =>
                j.launchId.isNotEmpty && j.repo.isNotEmpty && j.tag.isNotEmpty,
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  /// Saves a job identified by [launchId], [repo], and [tag], replacing any
  /// existing entry for the same [repo]/[tag] pair.
  Future<void> saveJob(String launchId, String repo, String tag) async {
    final prefs = await SharedPreferences.getInstance();
    final jobs =
        (await loadJobs())
            .where((j) => !(j.repo == repo && j.tag == tag))
            .toList()
          ..add(SavedJob(launchId: launchId, repo: repo, tag: tag));
    await prefs.setString(
      jobsKey,
      jsonEncode(jobs.map((j) => j.toJson()).toList()),
    );
  }

  /// Removes the saved job with the given [launchId].
  Future<void> removeJob(String launchId) async {
    final prefs = await SharedPreferences.getInstance();
    final jobs = (await loadJobs())
        .where((j) => j.launchId != launchId)
        .toList();
    await prefs.setString(
      jobsKey,
      jsonEncode(jobs.map((j) => j.toJson()).toList()),
    );
  }
}
