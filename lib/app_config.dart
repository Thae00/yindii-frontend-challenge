import 'package:flutter/material.dart';

abstract class AppConfig {
  static const appName = 'Rescu';

  static const primaryGreen = Color(0xFF2FB57C);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryGreen),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8F7),
        chipTheme: const ChipThemeData(
          side: BorderSide(color: Color(0xFFE0E5E2)),
        ),
      );
}
