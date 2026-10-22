import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Standard page: title area, responsive gutters and a maximum content width
/// so that wide screens use multi-column layouts instead of stretched text.
class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.body,
    super.key,
    this.subtitle,
    this.actions = const [],
    this.onRefresh,
    this.maxWidth = 1280,
    this.floatingActionButton,
    this.showBackButton = false,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  final Widget? floatingActionButton;
  final bool showBackButton;

  static EdgeInsets gutters(BuildContext context) {
    final size = WindowSize.of(context);
    final horizontal = switch (size) {
      WindowSize.compact => Spacing.md,
      WindowSize.medium => Spacing.lg,
      _ => Spacing.xl,
    };
    return EdgeInsets.fromLTRB(horizontal, Spacing.xs, horizontal, Spacing.xl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = showBackButton || Navigator.of(context).canPop();
    Widget content = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: canPop,
          title: Semantics(header: true, child: Text(title)),
          actions: [
            ...actions,
            const SizedBox(width: Spacing.xs),
          ],
          bottom: subtitle == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(24),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(start: canPop ? 72 : Spacing.md, bottom: Spacing.xs),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
        ),
        SliverPadding(
          padding: gutters(context),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: body,
              ),
            ),
          ),
        ),
      ],
    );
    if (onRefresh != null) content = RefreshIndicator(onRefresh: onRefresh!, child: content);
    return Scaffold(
      body: SafeArea(bottom: false, child: content),
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Lays children out in 1-3 columns depending on the available width.
class ResponsiveColumns extends StatelessWidget {
  const ResponsiveColumns({
    required this.children,
    super.key,
    this.minColumnWidth = 360,
    this.maxColumns = 3,
    this.spacing = Spacing.md,
  });

  final List<Widget> children;
  final double minColumnWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minColumnWidth).floor().clamp(1, maxColumns);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: spacing), children[i]],
            ],
          );
        }
        final buckets = List.generate(columns, (_) => <Widget>[]);
        for (var i = 0; i < children.length; i++) {
          buckets[i % columns].add(children[i]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < buckets[c].length; i++) ...[
                      if (i > 0) SizedBox(height: spacing),
                      buckets[c][i],
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A grid of equally sized stat tiles that wraps responsively.
class TileGrid extends StatelessWidget {
  const TileGrid({required this.children, super.key, this.minTileWidth = 170});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(1, 6);
        final width = (constraints.maxWidth - (columns - 1) * Spacing.sm) / columns;
        return Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}
