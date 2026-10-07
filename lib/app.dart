import 'package:flutter/material.dart';

import 'services/app_controller.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/theme.dart';

class LeadBookApp extends StatelessWidget {
  const LeadBookApp({super.key, required this.controller, this.theme});
  final AppController controller;

  /// Override for tests / documentation screenshots; defaults to [buildTheme].
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: theme ?? buildTheme(),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          // Larger text is supported up to 2x; beyond that layouts would break.
          minScaleFactor: 0.9,
          maxScaleFactor: 2.0,
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) =>
              controller.welcomeSeen ? const HomeShell() : const WelcomeScreen(),
        ),
      ),
    );
  }
}
