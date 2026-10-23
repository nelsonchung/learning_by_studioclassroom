import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learning_by_studioclassroom/data/lesson_repository.dart';
import 'package:learning_by_studioclassroom/domain/lesson.dart';

http.Response response(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status);

String fixture(String name) =>
    File('test/fixtures/$name.html').readAsStringSync();
String lineState(List<Map<String, Object>> episodes, {int year = 2026}) =>
    'window.__INITIAL_STATE__ = ${jsonEncode({
      'entities': {
        'dramaInfo': {
          'byId': {
            '42': {'svod': false, 'year': year, 'eps_info': episodes},
          },
        },
      },
    })};';

void main() {
  final now = DateTime.utc(2026, 10, 23, 4);
  LessonRepository repository(
    String index,
    String media, {
    Magazine magazine = Magazine.lt,
    bool failMedia = false,
  }) {
    return LessonRepository(
      now: () => now,
      client: MockClient((request) async {
        if (request.url.host == magazine.homeUri.host) {
          return response(index, 200);
        }
        if (request.url.host == 'm.studioclassroom.com') {
          return response(
            '<iframe src="https://www.linetv.tw/player/42/eps/1"></iframe>',
            200,
          );
        }
        return response(media, failMedia ? 503 : 200);
      }),
    );
  }

  test(
    'LT multi-day topic maps distinct dates to correct rolling episodes',
    () async {
      final repo = repository(
        fixture('lt_index'),
        lineState([
          {'number': 3, 'title': '1021 拍照技巧(上)'},
          {'number': 2, 'title': '1022 拍照技巧(下)'},
          {'number': 1, 'title': '1023 麵線'},
        ]),
      );
      addTearDown(repo.close);
      final lessons = await repo.load(Magazine.lt);
      expect(lessons.map((l) => l.date.day), [23, 22, 21, 20]);
      expect(lessons.map((l) => l.videoUri?.path), [
        '/player/42/eps/1',
        '/player/42/eps/2',
        '/player/42/eps/3',
        null,
      ]);
      expect(lessons[1].articleUri, lessons[2].articleUri);
      expect(lessons.last.title, isNull);
      expect(lessons.last.sourceFailed, isFalse);
    },
  );

  test('SC nested headings and summary are read from structural DOM', () async {
    final repo = repository(
      fixture('sc_index'),
      lineState([
        {'number': 1, 'title': '1023 新的地方(下)'},
        {'number': 2, 'title': '1022 其他主題'},
      ]),
      magazine: Magazine.sc,
    );
    addTearDown(repo.close);
    final lessons = await repo.load(Magazine.sc);
    expect(lessons.first.title, '新的地方');
    expect(lessons.first.englishTitle, 'A New Place');
    expect(lessons.first.summary, '認識世界');
    expect(lessons.first.videoUri, isNotNull);
    expect(
      lessons[1].videoUri,
      isNull,
      reason: 'Topic must match as well as date',
    );
  });

  test(
    'AD ignores commented anchors and maps real playlist metadata',
    () async {
      final playlist =
          'var ytInitialData = ${jsonEncode({
            'contents': [
              {
                'lockupViewModel': {
                  'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
                  'contentId': 'abcdefghijk',
                  'metadata': {
                    'lockupMetadataViewModel': {
                      'title': {'content': '【三日免費】(10/22) Our Brains 大腦'},
                    },
                  },
                },
              },
            ],
          })};';
      final repo = repository(
        fixture('ad_index'),
        playlist,
        magazine: Magazine.ad,
      );
      addTearDown(repo.close);
      final lessons = await repo.load(Magazine.ad);
      expect(lessons[1].title, '大腦');
      expect(lessons[1].articleUri, isNull);
      expect(lessons[1].videoUri?.queryParameters['v'], 'abcdefghijk');
      expect(lessons.first.title, isNull);
    },
  );

  test(
    'media failures preserve index and distinguish unavailable source',
    () async {
      final repo = repository(fixture('lt_index'), '', failMedia: true);
      addTearDown(repo.close);
      final lessons = await repo.load(Magazine.lt);
      expect(lessons.first.title, '麵線');
      expect(lessons.every((l) => l.sourceFailed), isTrue);
      expect(lessons.every((l) => l.videoUri == null), isTrue);
    },
  );

  test('refresh revalidates rolling mappings before playback', () async {
    var reads = 0;
    final repo = LessonRepository(
      now: () => now,
      client: MockClient((request) async {
        if (request.url.host == Magazine.lt.homeUri.host) {
          return response(fixture('lt_index'), 200);
        }
        if (request.url.host == 'm.studioclassroom.com') {
          return response(
            '<iframe src="https://www.linetv.tw/player/42/eps/1"></iframe>',
            200,
          );
        }
        reads++;
        return response(
          lineState([
            {'number': 1, 'title': reads == 1 ? '1023 麵線' : '1024 下一課'},
            if (reads > 1) {'number': 2, 'title': '1023 麵線'},
          ]),
          200,
        );
      }),
    );
    addTearDown(repo.close);
    expect((await repo.load(Magazine.lt)).first.videoUri?.path, endsWith('/1'));
    await repo.load(Magazine.lt);
    expect(reads, 1);
    expect(
      (await repo.load(Magazine.lt, refresh: true)).first.videoUri?.path,
      endsWith('/2'),
    );
  });

  test(
    'month rollover never relabels current index as requested prior month',
    () async {
      final repo = LessonRepository(
        now: () => DateTime.utc(2026, 11, 1),
        client: MockClient((request) async {
          if (request.url.host == Magazine.lt.homeUri.host) {
            return response(fixture('lt_index'), 200);
          }
          return response('', 503);
        }),
      );
      addTearDown(repo.close);
      final lessons = await repo.load(Magazine.lt);
      expect(lessons.map((l) => l.date.month), [11, 10, 10, 10]);
      expect(lessons.every((l) => l.title == null), isTrue);
    },
  );

  test(
    'Taipei date and previous year are taken from confirmed index',
    () async {
      final index = fixture('lt_index')
          .replaceAll('October 23', 'December 31')
          .replaceAll('2026-10-01', '2025-12-01');
      final repo = LessonRepository(
        now: () => DateTime.utc(2025, 12, 31, 17),
        client: MockClient((request) async {
          if (request.url.host == Magazine.lt.homeUri.host) {
            return response(index, 200);
          }
          if (request.url.host == 'm.studioclassroom.com') {
            return response(
              '<iframe src="https://www.linetv.tw/player/42/eps/1"></iframe>',
              200,
            );
          }
          return response(
            lineState([
              {'number': 2, 'title': '1231 麵線'},
            ], year: 2025),
            200,
          );
        }),
      );
      addTearDown(repo.close);
      final lessons = await repo.load(Magazine.lt);
      expect(lessons.first.date, DateTime.utc(2026, 1, 1));
      expect(lessons[1].date, DateTime.utc(2025, 12, 31));
      expect(lessons[1].videoUri?.path, endsWith('/2'));
    },
  );

  test('same-day cache expires after thirty minutes', () async {
    var instant = now;
    var indexReads = 0;
    final repo = LessonRepository(
      now: () => instant,
      client: MockClient((request) async {
        if (request.url.host == Magazine.lt.homeUri.host) {
          indexReads++;
          return response(fixture('lt_index'), 200);
        }
        return response('', 503);
      }),
    );
    addTearDown(repo.close);
    await repo.load(Magazine.lt);
    instant = instant.add(const Duration(minutes: 29));
    await repo.load(Magazine.lt);
    expect(indexReads, 1);
    instant = instant.add(const Duration(minutes: 1));
    await repo.load(Magazine.lt);
    expect(indexReads, 2);
  });

  test('entirely unavailable or unrecognized index fails explicitly', () async {
    final repo = LessonRepository(
      client: MockClient((_) async => response('', 503)),
    );
    addTearDown(repo.close);
    await expectLater(
      repo.load(Magazine.lt),
      throwsA(isA<http.ClientException>()),
    );
    final malformed = repository('<html>changed</html>', '');
    addTearDown(malformed.close);
    await expectLater(malformed.load(Magazine.lt), throwsFormatException);
  });
}
