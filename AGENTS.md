# Codebase context

  - The Flutter frontend uses the Flutter design system called Bison: https://github.com/fermi-ad/flutter-bison-design-system. When possible, prefer using widgets and theme tokens from Bison rather than base Flutter widgets or tokens. If you can't access the GitHub repo, look in the local pub cache to discover what Bison provides. This repo gets Bison from its flutter-controls-core dependency.

# Rules

  - When making code changes, do **not** add comments that only exist to explain context about why the change was made, mention details about an earlier version of the code, or implicitly compare the current state to the previous state.
  - When VS Code is running in a devcontainer, run dart and flutter commands as normal. When it's not running in a devcontainer, run these commands with fvm instead, if it's present. Checking once at the beginning of a conversation is fine.
