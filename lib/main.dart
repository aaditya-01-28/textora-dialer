import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/user_profile.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize theme mode from preferences
  final themeService = ThemeService();
  await themeService.init();

  // Dark status bar and navigation bar styling as default fallback
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F172A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Check persistent session
  final storage = StorageService();
  final token = await storage.getToken();
  final user = await storage.getUserProfile();

  runApp(TextoraDialerApp(initialUser: token != null ? user : null));
}

class TextoraDialerApp extends StatelessWidget {
  final UserProfile? initialUser;

  const TextoraDialerApp({super.key, this.initialUser});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().themeModeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Textora Dialer',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: initialUser != null
              ? HomeShell(user: initialUser!)
              : const LoginScreen(),
        );
      },
    );
  }
}
