import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../domain/lesson.dart';

class LessonRepository {
  LessonRepository({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;
  final Map<Magazine, List<DailyLesson>> _cache = {};
  final Map<Magazine, DateTime> _fetchedAt = {};

  Future<List<DailyLesson>> load(
    Magazine magazine, {
    bool refresh = false,
  }) async {
    final instant = _now().toUtc();
    final taipei = instant.add(const Duration(hours: 8));
    final today = DateTime.utc(taipei.year, taipei.month, taipei.day);
    final cached = _cache[magazine];
    if (!refresh &&
        cached != null &&
        cached.first.date == today &&
        instant.difference(_fetchedAt[magazine]!) <
            const Duration(minutes: 30)) {
      return cached;
    }
    final index = html.parse(await _get(magazine.homeUri));
    final courses = _courses(index, magazine);
    if (courses.isEmpty) {
      throw const FormatException('無法辨識官方課程目錄，請稍後重試。');
    }
    var mediaFailed = false;
    List<_Video> videos = [];
    try {
      videos = await _videos(index, magazine);
    } catch (_) {
      mediaFailed = true;
    }
    final lessons = List<DailyLesson>.generate(4, (offset) {
      final date = today.subtract(Duration(days: offset));
      final course = courses.where((c) => c.dates.contains(date)).firstOrNull;
      final video = videos.where((v) => v.matches(date, course)).firstOrNull;
      return DailyLesson(
        magazine: magazine,
        date: date,
        title: course?.title,
        englishTitle: course?.english,
        summary: course?.summary,
        articleUri: course?.uri,
        videoUri: video?.uri,
        videoLabel: video?.title,
        sourceFailed: mediaFailed,
      );
    });
    _fetchedAt[magazine] = instant;
    return _cache[magazine] = List.unmodifiable(lessons);
  }

  Future<String> _get(Uri uri) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException('來源回應 ${response.statusCode}', uri);
    }
    return utf8.decode(response.bodyBytes);
  }

  List<_Course> _courses(Document doc, Magazine magazine) {
    final blocks = doc.querySelectorAll(
      magazine == Magazine.lt ? '.lessonBOX' : '.index_article',
    );
    final result = <_Course>[];
    for (final block in blocks) {
      final dateText = _text(block, '.lessonDATE, .index_article_date');
      if (dateText == null) continue;
      final month =
          _months.indexWhere((m) => dateText.toLowerCase().contains(m)) + 1;
      if (month == 0) continue;
      // Read year/month from real DOM attributes, never commented anchors or
      // the requested URL: legacy sites silently ignore historical parameters.
      int? year;
      Uri? article;
      for (final anchor in block.querySelectorAll('a[href]')) {
        final uri = magazine.homeUri.resolve(anchor.attributes['href']!);
        if (uri.host != magazine.homeUri.host) continue;
        final volume = DateTime.tryParse(uri.queryParameters['volume'] ?? '');
        if (volume != null && volume.month == month) year = volume.year;
        if (uri.path.contains('article') && volume?.month == month) {
          article = uri;
        }
      }
      for (final image in block.querySelectorAll('img[src]')) {
        final match = RegExp(
          r'(?:LT|SC|AD)(\d{4})(\d{2})',
          caseSensitive: false,
        ).firstMatch(image.attributes['src']!);
        if (match != null && int.parse(match[2]!) == month) {
          year ??= int.parse(match[1]!);
        }
      }
      if (year == null) continue;
      final days = RegExp(r'\b\d{1,2}\b')
          .allMatches(dateText)
          .map((m) => int.parse(m[0]!))
          .where((d) => d > 0 && d <= 31);
      final dates = days
          .map((d) => DateTime.utc(year!, month, d))
          .where((d) => d.month == month)
          .toSet();
      final title =
          _text(block, '.lessonTITLE_c, .title-c-01') ??
          _text(block, '.a_cht_title > a') ??
          _text(block, '.a_cht_title');
      final english =
          _text(block, '.lessonTITLE_e, .beat-e') ??
          _text(block, '.article_en .a_eng_title');
      if (title == null && english == null) continue;
      result.add(
        _Course(
          dates,
          title,
          english,
          _text(block, '.teaser-c, .a_cht_subtitle_b'),
          article,
        ),
      );
    }
    return result;
  }

  Future<List<_Video>> _videos(Document index, Magazine magazine) async {
    if (magazine == Magazine.ad) {
      final embed = index
          .querySelectorAll('iframe[src]')
          .map((e) => Uri.tryParse(e.attributes['src']!))
          .whereType<Uri>()
          .where(
            (u) =>
                u.host == 'www.youtube.com' &&
                u.queryParameters.containsKey('list'),
          )
          .firstOrNull;
      if (embed == null) throw const FormatException('找不到官方播放清單');
      final page = await _get(
        Uri.https('www.youtube.com', '/playlist', {
          'list': embed.queryParameters['list']!,
        }),
      );
      final state = _jsonState(page, 'ytInitialData');
      final videos = <_Video>[];
      void visit(dynamic node) {
        if (node is Map) {
          final lockup = node['lockupViewModel'];
          if (lockup is Map &&
              lockup['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
            final id = lockup['contentId'];
            final title =
                lockup['metadata']?['lockupMetadataViewModel']?['title']?['content'];
            if (id is String &&
                title is String &&
                RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
              videos.add(
                _Video(
                  title,
                  Uri.https('www.youtube.com', '/watch', {'v': id}),
                ),
              );
            }
          }
          // Also support the legacy public playlist renderer.
          final renderer = node['playlistVideoRenderer'];
          if (renderer is Map && renderer['videoId'] is String) {
            final runs = renderer['title']?['runs'];
            if (runs is List) {
              final title = runs.map((r) => r['text'] ?? '').join();
              videos.add(
                _Video(
                  title,
                  Uri.https('www.youtube.com', '/watch', {
                    'v': renderer['videoId'],
                  }),
                ),
              );
            }
          }
          for (final value in node.values) {
            visit(value);
          }
        } else if (node is List) {
          for (final value in node) {
            visit(value);
          }
        }
      }

      visit(state);
      if (videos.isEmpty) throw const FormatException('無法辨識官方影片清單');
      return videos;
    }
    final official = Uri.https('m.studioclassroom.com', '/tv-programs.php', {
      'level': magazine.code,
    });
    final page = html.parse(await _get(official));
    final player = page
        .querySelectorAll('iframe[src]')
        .map((e) => Uri.tryParse(e.attributes['src']!))
        .whereType<Uri>()
        .where(
          (u) =>
              u.host == 'www.linetv.tw' &&
              RegExp(r'^/player/\d+/eps/\d+$').hasMatch(u.path),
        )
        .firstOrNull;
    if (player == null) throw const FormatException('找不到官方播放器');
    final state = _jsonState(await _get(player), '__INITIAL_STATE__');
    final dramaId = player.pathSegments[1];
    final info = state['entities']?['dramaInfo']?['byId']?[dramaId];
    if (info is! Map || info['eps_info'] is! List) {
      throw const FormatException('無法辨識官方節目清單');
    }
    if (info['svod'] != false) return [];
    return (info['eps_info'] as List)
        .whereType<Map>()
        .where(
          (episode) =>
              episode['svod'] != true &&
              episode['number'] is num &&
              episode['title'] is String,
        )
        .map(
          (episode) => _Video(
            episode['title'] as String,
            player.replace(path: '/player/$dramaId/eps/${episode['number']}'),
            year: info['year'] is int ? info['year'] as int : null,
          ),
        )
        .toList();
  }

  void close() => _client.close();
}

const _months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];
String? _text(Element block, String selector) {
  final value = block
      .querySelector(selector)
      ?.text
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return value == null || value.isEmpty ? null : value;
}

// Extract balanced JSON, respecting quoted braces and escaped characters.
Map<String, dynamic> _jsonState(String page, String marker) {
  final assignment = RegExp(
    '${RegExp.escape(marker)}["\']?\\s*=\\s*',
  ).firstMatch(page);
  if (assignment == null) throw FormatException('Missing $marker');
  final start = page.indexOf('{', assignment.end);
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var i = start; start >= 0 && i < page.length; i++) {
    final char = page[i];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == '{') {
      depth++;
    } else if (char == '}' && --depth == 0) {
      return jsonDecode(page.substring(start, i + 1)) as Map<String, dynamic>;
    }
  }
  throw FormatException('Invalid $marker');
}

class _Course {
  _Course(this.dates, this.title, this.english, this.summary, this.uri);
  final Set<DateTime> dates;
  final String? title;
  final String? english;
  final String? summary;
  final Uri? uri;
}

class _Video {
  _Video(this.title, this.uri, {this.year});
  final String title;
  final Uri uri;
  final int? year;
  bool matches(DateTime date, _Course? course) {
    if (course == null || (year != null && year != date.year)) return false;
    final explicitYear = RegExp(
      r'\b(20\d{2})[/.-]\d{1,2}[/.-]\d{1,2}',
    ).firstMatch(title);
    if (explicitYear != null && int.parse(explicitYear[1]!) != date.year) {
      return false;
    }
    final match = RegExp(
      r'(?:^|[^\d])(\d{1,2})/(\d{1,2})(?:[^\d]|$)',
    ).firstMatch(title);
    final compact = RegExp(r'^(\d{2})(\d{2})(?:[^\d]|$)').firstMatch(title);
    final month = int.tryParse(match?[1] ?? compact?[1] ?? '');
    final day = int.tryParse(match?[2] ?? compact?[2] ?? '');
    if (month != date.month || day != date.day) return false;
    String normalize(String text) =>
        text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff]'), '');
    final normalized = normalize(title);
    return [course.title, course.english].whereType<String>().any(
      (topic) =>
          normalize(topic).isNotEmpty && normalized.contains(normalize(topic)),
    );
  }
}
