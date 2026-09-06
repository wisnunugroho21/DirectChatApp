import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff147d72),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.outline),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      selectedTileColor: colors.secondaryContainer,
      selectedColor: colors.onSecondaryContainer,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
