import 'package:flutter/material.dart';

import 'screens/login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sprint',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C3192),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F2FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF3F2FF),
          foregroundColor: Color(0xFF272C8C),
          elevation: 0,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2C3192),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF272C8C),
            side: const BorderSide(color: Color(0x662C3192)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
