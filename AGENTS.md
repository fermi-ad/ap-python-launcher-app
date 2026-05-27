# Codebase context

  - The Flutter frontend uses the private Flutter design system called Bison: https://github.com/fermi-ad/flutter-bison-design-system. When possible, prefer using widgets and theme tokens from Bison rather than base Flutter widgets or tokens. If you can't access the GitHub repo, look in the local pub cache to discover what Bison provides: ~/.pub-cache/git/design-system...

# Rules

  - When making code changes, do **not** add comments that only exist to explain context about why the change was made, mention details about an earlier version of the code, or implicitly compare the current state to the previous state.
  - Use fvm when running Flutter commands. If you don't have access to the fvm command, run Flutter with .fvm/flutter_sdk/bin/flutter instead.
  - This project uses uv for Python package management. Use uv commands instead of pip. When running Python commands, use the Python executable at .venv/bin/python, and prepend PYTHONPATH=./src to your command.
