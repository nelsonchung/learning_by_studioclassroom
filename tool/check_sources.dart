import 'dart:convert';
import 'dart:io';

import 'package:learning_by_studioclassroom/data/lesson_repository.dart';
import 'package:learning_by_studioclassroom/domain/lesson.dart';

/// Optional live smoke check; automated tests use synthetic, offline fixtures.
Future<void> main() async {
  final repository = LessonRepository();
  try {
    for (final magazine in Magazine.values) {
      try {
        final lessons = await repository.load(magazine, refresh: true);
        stdout.writeln(
          jsonEncode({
            'magazine': magazine.code,
            'lessons': [
              for (final lesson in lessons)
                {
                  'date': lesson.date.toIso8601String().substring(0, 10),
                  'title': lesson.title,
                  'video': lesson.videoUri?.toString(),
                  'sourceFailed': lesson.sourceFailed,
                },
            ],
          }),
        );
        if (lessons.length != 4 || lessons.any((item) => item.sourceFailed)) {
          exitCode = 1;
        }
      } catch (error) {
        stderr.writeln('${magazine.code}: $error');
        exitCode = 1;
      }
    }
  } finally {
    repository.close();
  }
}
