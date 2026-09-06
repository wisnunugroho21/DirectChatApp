import 'package:flutter/material.dart';

/// Colors and dimensions from Legacy/wwwroot/css/chat.css.
abstract final class LegacyStyle {
  static const panel = Color(0xffffffff);
  static const sidebar = Color(0xfff6f9fd);
  static const border = Color(0xffdce6f2);
  static const text = Color(0xff102a43);
  static const muted = Color(0xff667b91);
  static const accent = Color(0xff2563eb);
  static const accentDark = Color(0xff1d4ed8);
  static const soft = Color(0xffe8f1ff);
  static const success = Color(0xff10b981);
  static const danger = Color(0xffdc2626);
  static const sidebarWidth = 390.0;
  static const headerHeight = 72.0;
  static const mobileBreakpoint = 900.0;
  static const shadow = [
    BoxShadow(color: Color(0x0d0f2742), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0a0f2742), blurRadius: 14, offset: Offset(0, 4)),
  ];
}

// Material provides text editing, selection and route infrastructure only.
// All visible controls use the legacy styles, with no Material ink or M3 surfaces.
ThemeData buildAppTheme([Brightness brightness = Brightness.light]) {
  const colors = ColorScheme.light(
    primary: LegacyStyle.accent,
    onPrimary: Colors.white,
    primaryContainer: LegacyStyle.soft,
    onPrimaryContainer: LegacyStyle.accentDark,
    surface: Colors.white,
    onSurface: LegacyStyle.text,
    onSurfaceVariant: LegacyStyle.muted,
    outline: LegacyStyle.border,
    outlineVariant: LegacyStyle.border,
    error: LegacyStyle.danger,
  );
  return ThemeData(
    useMaterial3: false,
    brightness: Brightness.light,
    colorScheme: colors,
    scaffoldBackgroundColor: LegacyStyle.sidebar,
    fontFamily: 'Roboto',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        fontSize: 14.5,
        height: 1.4,
        color: LegacyStyle.text,
      ),
      bodyLarge: TextStyle(
        fontSize: 14.5,
        height: 1.48,
        color: LegacyStyle.text,
      ),
      bodySmall: TextStyle(fontSize: 12.5, color: LegacyStyle.muted),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: LegacyStyle.text,
      ),
    ),
    iconTheme: const IconThemeData(size: 24, color: LegacyStyle.muted),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      hintStyle: TextStyle(
        color: LegacyStyle.muted,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: LegacyStyle.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: LegacyStyle.border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: LegacyStyle.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Color(0xff93b9f7)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: LegacyStyle.text,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );
}
