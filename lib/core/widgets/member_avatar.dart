import 'package:material_ui/material_ui.dart';

/// Initials on a warm background derived from the name, so every member keeps
/// the same color everywhere.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({required this.name, super.key, this.radius = 18, this.imageUrl});

  final String name;
  final double radius;
  final String? imageUrl;

  static const _tones = [
    (Color(0xFFE9D9C9), Color(0xFF3E2723)),
    (Color(0xFFF6DFC4), Color(0xFF5A3A16)),
    (Color(0xFFD5E8DC), Color(0xFF1F3F2E)),
    (Color(0xFFF2DCD7), Color(0xFF5A2A26)),
    (Color(0xFFE4DEEF), Color(0xFF3B3150)),
    (Color(0xFFDCE7EF), Color(0xFF243B4E)),
    (Color(0xFFEFE6C9), Color(0xFF4D4013)),
  ];

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tone = _tones[name.codeUnits.fold<int>(0, (sum, unit) => (sum * 31 + unit) & 0x7fffffff) % _tones.length];
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: tone.$1,
        foregroundImage: imageUrl == null ? null : NetworkImage(imageUrl!),
        child: Text(
          initials(name),
          style: TextStyle(color: tone.$2, fontWeight: FontWeight.w600, fontSize: radius * 0.8, height: 1),
        ),
      ),
    );
  }
}
