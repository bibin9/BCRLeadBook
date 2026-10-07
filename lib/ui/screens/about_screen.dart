import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';

class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 88});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kBlue,
          borderRadius: BorderRadius.circular(size * 0.24),
          boxShadow: const [BoxShadow(color: Color(0x331565C0), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Icon(Icons.menu_book_rounded, color: Colors.white, size: size * 0.56),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Center(child: AppMark()),
          const SizedBox(height: 16),
          const Center(
            child: Text(kAppName, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kBlueDark)),
          ),
          const SizedBox(height: 4),
          const Center(child: Text('Version $kAppVersion', style: TextStyle(color: kMuted))),
          const SizedBox(height: 20),
          const Text(
            'A personal lead and relationship tracker for insurance sales professionals. Record a client meeting in under five minutes, then recall the important details before the next call.',
            style: TextStyle(fontSize: 16, height: 1.45),
          ),
          const SizedBox(height: 16),
          for (final line in const [
            'Works fully offline. No account or subscription.',
            'Records are stored only on this phone; the app never sends them anywhere.',
            'No analytics, no AI services, no remote servers.',
            'Back up regularly: records are lost if the app is uninstalled or the phone is lost.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle, size: 20, color: kBlue),
                const SizedBox(width: 10),
                Expanded(child: Text(line, style: const TextStyle(fontSize: 15.5, height: 1.35))),
              ]),
            ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 16),
          const Center(child: Text('Crafted by', style: TextStyle(color: kMuted, fontSize: 13))),
          const SizedBox(height: 4),
          const Signature(large: true),
        ],
      ),
    );
  }
}
