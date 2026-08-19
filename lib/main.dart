import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'services/game_feedback_service.dart';
import 'widgets/game_feedback_scope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GameFeedbackService _feedbackService;

  @override
  void initState() {
    super.initState();
    _feedbackService = GameFeedbackService()..attachToAppLifecycle();
    unawaited(_feedbackService.initialize());
  }

  @override
  void dispose() {
    _feedbackService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameFeedbackScope(
      service: _feedbackService,
      child: MaterialApp(
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
      ),
    );
  }
}
