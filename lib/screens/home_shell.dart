import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'dashboard_screen.dart';
import 'leads_screen.dart';
import 'call_history_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  final UserProfile user;

  const HomeShell({super.key, required this.user});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  late UserProfile _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  void _onProfileUpdated(UserProfile updated) {
    setState(() => _currentUser = updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final navBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final unselected = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const selected = Color(0xFF10B981);

    final screens = [
      DashboardScreen(
        user: _currentUser,
        onNavigateToLeads: () => setState(() => _currentIndex = 1),
      ),
      LeadsScreen(user: _currentUser),
      const CallHistoryScreen(),
      ProfileScreen(
        user: _currentUser,
        onProfileUpdated: _onProfileUpdated,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(top: BorderSide(color: navBorder, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: selected,
          unselectedItemColor: unselected,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
              tooltip: 'Sales Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts_outlined),
              activeIcon: Icon(Icons.contacts_rounded),
              label: 'Leads',
              tooltip: 'Calling Leads Queue',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.phone_callback_outlined),
              activeIcon: Icon(Icons.phone_callback_rounded),
              label: 'Calls',
              tooltip: 'Carrier Call Records',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
              tooltip: 'User Level & Accessibility',
            ),
          ],
        ),
      ),
    );
  }
}
