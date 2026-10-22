/// Route paths. Keep in sync with the router and the navigation destinations.
abstract final class Routes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const verifyEmail = '/verify-email';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const welcome = '/welcome';
  static const createGroup = '/create-group';
  static const join = '/join';

  static const home = '/home';
  static const group = '/group';
  static const activity = '/activity';
  static const heroes = '/heroes';
  static const analytics = '/analytics';
  static const settle = '/settle';
  static const cycles = '/cycles';
  static const admin = '/admin';
  static const settings = '/settings';
  static const notifications = '/notifications';
  static const more = '/more';

  static String joinWithCode(String code) => '$join/$code';
  static String member(String userId) => '$group/member/$userId';
  static String transaction(String id) => '$activity/$id';
  static String cycle(String id) => '$cycles/$id';
  static String adminSection(String section) => '$admin/$section';

  static const authRoutes = {signIn, signUp, verifyEmail, forgotPassword};

  /// Reachable while signed in without belonging to any group.
  static bool allowedWithoutGroup(String location) =>
      location == welcome || location == createGroup || location.startsWith(join) || location.startsWith(settings);
}
