import 'package:http/browser_client.dart' show BrowserClient;
import 'package:http/http.dart' show Client;

/// Creates a browser HTTP client that sends credentials with requests.
Client createHttpClient() => BrowserClient()..withCredentials = true;
