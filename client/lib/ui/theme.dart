import 'package:flutter/material.dart';
import 'package:rps_shared/rps_shared.dart';
import 'i18n.dart' as i18n;

/// Palette taken from the RPS logo (navy disc, gold rim, cream banner, blue ribbon).
/// Light/dark: [dark] switches the surface and text colours (navy*, cream,
/// fg); accent colours (gold, blue, team, danger) are the same in both.
abstract final class Rps {
  /// Current theme; set from Settings.dark (saved on the server).
  static bool dark = true;

  // Surfaces: dark navy in dark mode, warm paper tones in light mode.
  static Color get navy => dark ? const Color(0xFF1E2557) : const Color(0xFFE9E2D0);
  static Color get navyDeep => dark ? const Color(0xFF0D1233) : const Color(0xFFF7F3EA);
  static Color get navyMid => dark ? const Color(0xFF2B3A86) : const Color(0xFFD9CDB0);

  /// Main text colour (cream on dark, navy ink on light).
  static Color get cream => dark ? const Color(0xFFF4EEE2) : const Color(0xFF1A2050);

  /// Secondary text / borders at [a] opacity of the main text colour.
  static Color fg(double a) => cream.withValues(alpha: a);

  /// Text on gold buttons/badges (always dark).
  static const onGold = Color(0xFF0D1233);
  static const gold = Color(0xFFE8B04A);

  /// Gold for text: deeper in light mode so it reads on paper tones.
  static Color get goldText => dark ? gold : const Color(0xFF94640A);
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
    final b = dark ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansKR',
      brightness: b,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1E2557),
        brightness: b,
        primary: dark ? gold : const Color(0xFFB07A12),
        onPrimary: onGold,
        secondary: blue,
        surface: navyDeep,
        onSurface: cream,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: cream, displayColor: cream),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: onGold,
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
