import 'package:web/web.dart' show window;

/// Opens [url] in a new browser tab using the web platform.
void openInNewTab(final String url) {
  window.open(url, '_blank');
}

/// Navigates the current browser tab to [url].
void navigateTo(final String url) {
  window.location.href = url;
}
