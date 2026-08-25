import 'package:http/browser_client.dart' show BrowserClient;
import 'package:http/http.dart' show Client;

Client createHttpClient() => BrowserClient()..withCredentials = true;
