import 'package:web/web.dart' show window;

/// Opens [url] in a new browser tab using the web platform.
void openInNewTab(String url) {
  window.open(url, '_blank');
}
