/* 
  Sets up a git pre-commit hook in .git/hooks/pre-commit that runs
  dart_pre_commit
 */
import 'dart:io' show File, Platform, Process, exitCode, stderr, stdout;

Future<void> main() async {
  final preCommitHook = File('.git/hooks/pre-commit');
  await preCommitHook.parent.create();
  await preCommitHook.writeAsString(r'''
#!/bin/sh

repo_root="$(git rev-parse --show-toplevel)" || exit 1
fvm_dart="$repo_root/.fvm/flutter_sdk/bin/dart"

if [ -x "$fvm_dart" ]; then
  export PATH="$(dirname "$fvm_dart"):$PATH"
  exec "$fvm_dart" run dart_pre_commit
fi

exec dart run dart_pre_commit
''');

  if (!Platform.isWindows) {
    final result = await Process.run('chmod', ['a+x', preCommitHook.path]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
  }
}
