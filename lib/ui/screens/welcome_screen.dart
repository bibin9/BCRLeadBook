import 'package:flutter/material.dart';

import '../../services/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
              children: [
                const Center(child: AppMark(size: 104)),
                const SizedBox(height: 24),
                const Text(
                  'Welcome to\n$kAppName',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: kBlueDark, height: 1.15),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Record a client meeting in under five minutes, then remember every detail before the next call.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, color: kMuted, height: 1.4),
                ),
                const SizedBox(height: 28),
                for (final (icon, text) in const [
                  (Icons.bolt, 'Type straight away. Only the company name is required.'),
                  (Icons.sticky_note_2_outlined, 'Keep meeting notes, rapport details and company context together.'),
                  (Icons.notifications_none, 'Get a private reminder for every follow-up. See renewals at a glance.'),
                  (Icons.lock_outline, 'Works offline. The app never sends your records anywhere.'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(icon, color: kBlue, size: 26),
                      const SizedBox(width: 14),
                      Expanded(child: Text(text, style: const TextStyle(fontSize: 16, height: 1.35))),
                    ]),
                  ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: app.markWelcomeSeen,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                  child: const Text('Get started', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 28),
                const Signature(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
