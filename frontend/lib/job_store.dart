import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;

const jobsKey = 'ap_python_launcher_jobs';

class SavedJob {
  SavedJob({required this.launchId, required this.repo, required this.tag});

  factory SavedJob.fromJson(Map<String, dynamic> json) {
    return SavedJob(
      launchId: (json['launchId'] as String?) ?? '',
      repo: (json['repo'] as String?) ?? '',
      tag: (json['tag'] as String?) ?? '',
    );
  }
  final String launchId;
  final String repo;
  final String tag;

  Map<String, dynamic> toJson() => {
    'launchId': launchId,
    'repo': repo,
    'tag': tag,
  };
}

class JobStore {
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
    } on Exception {
      return const [];
    }
  }

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
