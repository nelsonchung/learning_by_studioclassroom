import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/lesson_repository.dart';
import 'features/library/library_page.dart';
import 'preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.repository, this.preferences});
  final LessonRepository? repository;
  final PreferencesStore? preferences;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '今日英語',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xffB65D43),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xffB65D43),
            onPrimary: Colors.white,
            surface: const Color(0xffF8F7F3),
            onSurface: const Color(0xff262521),
            onSurfaceVariant: const Color(0xff77736C),
            outlineVariant: const Color(0xffE2DFD7),
          ),
      dividerTheme: const DividerThemeData(
        color: Color(0xffE2DFD7),
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xff77736C),
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
      scaffoldBackgroundColor: const Color(0xffF8F7F3),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xffF8F7F3),
        surfaceTintColor: Colors.transparent,
      ),
    ),
    home: LibraryPage(repository: repository, preferences: preferences),
  );
}
