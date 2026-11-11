import 'package:flutter/material.dart';
import 'package:rps_shared/rps_shared.dart';
import 'i18n.dart' as i18n;

/// Palette taken from the RPS logo (navy disc, gold rim, cream banner, blue ribbon).
abstract final class Rps {
  static const navy = Color(0xFF1E2557);
  static const navyDeep = Color(0xFF0D1233);
  static const navyMid = Color(0xFF2B3A86);
  static const gold = Color(0xFFE8B04A);
  static const cream = Color(0xFFF4EEE2);
  static const blue = Color(0xFF3F7BE0);
  static const teamA = Color(0xFFFF8A2A); // orange spawn (z+)
  static const teamB = Color(0xFF4D8CF0); // blue spawn (z-)
  static const danger = Color(0xFFE5484D);

  static Color team(int t) => t == 0 ? teamA : teamB;
  static String teamName(int t) => i18n.teamName(t);

  static Color role(Role r) => switch (r) {
        Role.defender => const Color(0xFF8C9BB0),
        Role.attack => const Color(0xFFE5674D),
        Role.healer => const Color(0xFF4DC9A0),
        Role.controller => const Color(0xFF9B7BEA),
      };

  static IconData roleIcon(Role r) => switch (r) {
        Role.defender => Icons.shield,
        Role.attack => Icons.bolt,
        Role.healer => Icons.add_circle,
        Role.controller => Icons.blur_on,
      };

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansKR',
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: navy,
        brightness: Brightness.dark,
        primary: gold,
        secondary: blue,
        surface: navyDeep,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: cream, displayColor: cream),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: navyDeep,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 1),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

/// Keyboard key for each skill slot: Q, E, C, V(ult).
String skillKeyLabel(SkillKey k) => switch (k) {
      SkillKey.q => 'Q',
      SkillKey.e => 'E',
      SkillKey.shift => 'C',
      SkillKey.ult => 'V',
    };

/// Icon images from rps_assets/icons (copied by tool/sync_assets.dart).
Widget charIcon(String id, double size) => _icon('assets/icons/char/$id.png', size, size);
Widget skillIcon(String id, double size, {bool dim = false}) =>
    Opacity(opacity: dim ? 0.35 : 1, child: _icon('assets/icons/skill/$id.png', size, size));
Widget gunIcon(String id, double w, double h) => _icon('assets/icons/gun/$id.png', w, h);
Widget roleIcon(Role r, double size) => _icon('assets/icons/role/${r.name}.png', size, size);

Widget _icon(String path, double w, double h) => Image.asset(path,
    width: w,
    height: h,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => SizedBox(width: w, height: h));

/// Translucent navy panel used across menus and HUD.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.opacity = 0.82});
  final Widget child;
  final EdgeInsets padding;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Rps.navyDeep.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Rps.gold.withValues(alpha: 0.35)),
        ),
        child: child,
      );
}
