import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Wraps [child] like the real app: theme, localizations and providers.
Widget testApp(
  Widget child, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  bool dark = false,
}) {
  return ProviderScope(
    overrides: overrides,
    retry: (_, _) => null,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: locale,
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

/// Sets the logical screen size for the rest of the test.
void setScreenSize(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
}

const phone = Size(400, 860);
const tablet = Size(700, 1000);
const desktop = Size(1400, 900);
