import 'package:ap_python_launcher_app/auth_service.dart' as auth;

class FakeAuthService implements auth.AuthService {
  FakeAuthService({auth.AuthStatus? status})
    : status = status ?? auth.AuthStatus(authenticated: true);

  auth.AuthStatus status;

  int getAuthStatusCalls = 0;
  int loginCalls = 0;
  int logoutCalls = 0;

  @override
  Future<auth.AuthStatus> getAuthStatus() async {
    getAuthStatusCalls += 1;
    return status;
  }

  @override
  void login() {
    loginCalls += 1;
  }

  @override
  void logout() {
    logoutCalls += 1;
  }
}
