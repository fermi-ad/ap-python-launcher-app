import 'package:web/web.dart' as web;

void openInNewTab(String url) {
  web.window.open(url, '_blank');
}
