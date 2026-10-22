/// Compile-time configuration, passed with `--dart-define-from-file`.
///
/// Only the public Supabase URL and publishable key are ever compiled into
/// the app; both are safe to expose because Row Level Security protects the
/// data. Service-role keys must never be passed here.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.environment,
    required this.webRedirectUrl,
    this.publicAppUrl = '',
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    environment: String.fromEnvironment('APP_ENV', defaultValue: 'development'),
    webRedirectUrl: String.fromEnvironment('WEB_REDIRECT_URL'),
    publicAppUrl: String.fromEnvironment('PUBLIC_APP_URL'),
  );

  /// Deep link used by the mobile apps to return from email links.
  static const mobileRedirectUrl = 'io.github.mamir1998.coffeetracker://login-callback';

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String environment;

  /// Optional override for the web redirect target; defaults to the origin
  /// the web app is served from.
  final String webRedirectUrl;

  /// Public address of the web app (e.g. https://coffee.example.org), used to
  /// build invitation links in the native apps. Optional.
  final String publicAppUrl;

  bool get isProduction => environment == 'production';

  /// Human-readable configuration problems; empty when the app can start.
  List<String> get problems {
    final problems = <String>[];
    final uri = Uri.tryParse(supabaseUrl);
    if (supabaseUrl.isEmpty) {
      problems.add('SUPABASE_URL is not set.');
    } else if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      problems.add('SUPABASE_URL is not a valid URL.');
    } else if (isProduction && uri.scheme != 'https') {
      problems.add('Production builds must use an https Supabase URL.');
    }
    if (supabasePublishableKey.isEmpty) {
      problems.add('SUPABASE_PUBLISHABLE_KEY is not set.');
    } else if (supabasePublishableKey.startsWith('sb_secret_')) {
      problems.add('A secret key was configured. Use the publishable key instead.');
    }
    return problems;
  }

  bool get isValid => problems.isEmpty;
}
