import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'entry_screen.dart';
import 'followups_screen.dart';
import 'leads_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          DashboardScreen(goToTab: (i) => setState(() => index = i)),
          const LeadsScreen(),
          const FollowUpsScreen(),
          const SettingsScreen(),
        ],
      ),
      floatingActionButton: index == 1 || index == 2
          ? FloatingActionButton.extended(
              onPressed: () => startEntry(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Lead / Meeting'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Leads'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Follow-ups'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
