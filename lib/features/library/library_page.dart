import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/lesson_repository.dart';
import '../../domain/lesson.dart';
import '../../preferences.dart';
import '../media/player_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    this.repository,
    this.preferences,
    this.playerBuilder,
  });
  final LessonRepository? repository;
  final PreferencesStore? preferences;
  final Widget Function(Uri uri, String title)? playerBuilder;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with WidgetsBindingObserver {
  late final LessonRepository _repository;
  late final PreferencesStore _preferences;
  Magazine _magazine = Magazine.lt;
  List<DailyLesson> _lessons = [];
  int _selected = 0;
  int _request = 0;
  int _selectionRevision = 0;
  bool _loading = true;
  bool _opening = false;
  String? _error;
  late String _today;
  Timer? _timer;

  String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';
  String _taipeiToday() =>
      _dayKey(DateTime.now().toUtc().add(const Duration(hours: 8)));

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? LessonRepository();
    _preferences = widget.preferences ?? PreferencesStore();
    _today = _taipeiToday();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkDate());
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final revision = _selectionRevision;
    try {
      final saved = await _preferences.loadMagazine();
      if (!mounted) return;
      if (saved != null && revision == _selectionRevision) {
        setState(() => _magazine = saved);
      }
    } catch (_) {
      // Preference failures must not prevent lessons from loading.
    }
    if (mounted) await _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkDate();
  }

  void _checkDate() {
    final today = _taipeiToday();
    if (today == _today || !mounted) return;
    _today = today;
    _selected = 0;
    unawaited(_load(refresh: true));
  }

  Future<void> _load({bool refresh = false}) async {
    final request = ++_request;
    final magazine = _magazine;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lessons = await _repository.load(magazine, refresh: refresh);
      if (!mounted || request != _request) return;
      setState(() {
        _lessons = lessons;
        _selected = _selected.clamp(
          0,
          lessons.isEmpty ? 0 : lessons.length - 1,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _lessons = [];
        _loading = false;
        _error = '暫時無法取得課程，請確認網路後重試。';
      });
    }
  }

  void _changeMagazine(Magazine magazine) {
    _selectionRevision++;
    if (_magazine == magazine) return;
    setState(() => _magazine = magazine);
    unawaited(_saveMagazine(magazine));
    unawaited(_load());
  }

  Future<void> _saveMagazine(Magazine magazine) async {
    try {
      await _preferences.saveMagazine(magazine);
    } catch (_) {
      // The current selection still works without persistent preferences.
    }
  }

  Future<void> _openOfficial(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _notify('無法開啟官方頁面，請稍後再試。');
      }
    } catch (_) {
      _notify('無法開啟官方頁面，請稍後再試。');
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _watch(DailyLesson lesson) async {
    if (_opening) return;
    final request = _request;
    setState(() => _opening = true);
    try {
      // Provider episode slots roll daily: resolve the date again before play.
      final fresh = await _repository.load(_magazine, refresh: true);
      if (!mounted || request != _request) return;
      final matches = fresh.where(
        (item) => _dayKey(item.date) == _dayKey(lesson.date),
      );
      final current = matches.isEmpty ? null : matches.first;
      final stillSelected =
          _lessons.isNotEmpty &&
          _dayKey(_lessons[_selected].date) == _dayKey(lesson.date);
      setState(() => _lessons = fresh);
      if (!stillSelected) return;
      if (current?.videoUri == null) {
        _notify(
          current?.sourceFailed == true
              ? '影片清單暫時無法確認，請稍後重試。'
              : '重新確認後，這天目前沒有可用影片。請查看課程狀態。',
        );
        return;
      }
      final uri = current!.videoUri!;
      final title = current.title ?? current.englishTitle ?? _magazine.label;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              widget.playerBuilder?.call(uri, title) ??
              PlayerPage(videoUri: uri, title: title),
        ),
      );
      if (mounted) _checkDate();
    } catch (_) {
      _notify('暫時無法確認影片日期，請重新整理後再試。');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.repository == null) _repository.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DAILY ENGLISH',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2.2,
                              fontWeight: FontWeight.w700,
                              color: Color(0xffB65D43),
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            '空英隨學',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '重新整理',
                      onPressed: _loading ? null : () => _load(refresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final magazine in Magazine.values)
                      _MagazineTab(
                        magazine: magazine,
                        selected: _magazine == magazine,
                        onTap: () => _changeMagazine(magazine),
                      ),
                  ],
                ),
                const SizedBox(height: 26),
                const Divider(height: 1),
                const SizedBox(height: 22),
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        '最近四天',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '台北時間',
                      style: TextStyle(fontSize: 11, color: Color(0xff77736C)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: '載入課程',
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (_error != null)
                  _ErrorCard(
                    message: _error!,
                    retry: () => _load(refresh: true),
                    official: () => _openOfficial(_magazine.homeUri),
                  )
                else if (_lessons.isEmpty)
                  _ErrorCard(
                    message: '目前尚無課程資料。',
                    retry: () => _load(refresh: true),
                    official: () => _openOfficial(_magazine.homeUri),
                  )
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth < 300 ||
                              MediaQuery.textScalerOf(context).scale(14) > 20
                          ? 2
                          : 4;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var index = 0; index < _lessons.length; index++)
                            SizedBox(
                              width:
                                  (constraints.maxWidth - (columns - 1) * 8) /
                                  columns,
                              child: _DateButton(
                                date: _lessons[index].date,
                                label: const ['今天', '昨天', '前天', '前三天'][index],
                                selected: index == _selected,
                                onTap: () => setState(() => _selected = index),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  _lessonCard(_lessons[_selected]),
                ],
                const SizedBox(height: 28),
                const Divider(height: 1),
                const SizedBox(height: 16),
                const Text(
                  '影片由官方平台提供，免費開放日期依來源更新。文章與獨立廣播可能需要官方會員或訂閱。',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.7,
                    color: Color(0xff77736C),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _lessonCard(DailyLesson lesson) {
    final available = lesson.videoUri != null;
    final color = Theme.of(context).colorScheme;
    final unconfirmed = lesson.title == null && lesson.englishTitle == null;
    final status = available
        ? '每日節目・可播放'
        : lesson.sourceFailed
        ? '來源暫時無法讀取'
        : unconfirmed
        ? '課程資料尚未確認'
        : '目前免費清單未列出';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xffEDE5DC),
                border: Border(
                  left: BorderSide(color: Color(0xffB65D43), width: 3),
                ),
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(4),
                ),
              ),
              child: Text(
                _magazine.code.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xff8B4935),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _magazine.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${lesson.date.year} 年 ${lesson.date.month} 月 ${lesson.date.day} 日',
                    style: TextStyle(
                      fontSize: 11,
                      color: color.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          lesson.englishTitle ?? 'Daily English',
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 30,
            height: 1.2,
            letterSpacing: -0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          lesson.title ?? '這天的課程尚未確認',
          style: TextStyle(
            fontSize: 18,
            height: 1.5,
            color: color.onSurfaceVariant,
          ),
        ),
        if (lesson.summary != null && lesson.summary!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            lesson.summary!,
            style: TextStyle(
              fontSize: 14,
              height: 1.8,
              color: color.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: available ? color.primary : color.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  color: available ? color.primary : color.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (!available) ...[
          const SizedBox(height: 9),
          Text(
            lesson.sourceFailed
                ? '請重新整理後再試，或前往官方節目頁。'
                : unconfirmed
                ? '官方目前的目錄尚無可核對的資料，請前往官方頁面查看。'
                : '這不代表當天沒有節目；官方免費回看通常僅提供最近三集。',
            style: TextStyle(
              fontSize: 13,
              height: 1.7,
              color: color.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: available && !_opening ? () => _watch(lesson) : null,
            icon: _opening
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 24),
            label: Text(_opening ? '確認影片中…' : '觀看每日節目'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () =>
              _openOfficial(lesson.articleUri ?? _magazine.homeUri),
          icon: const Icon(Icons.north_east_rounded, size: 15),
          label: Text(lesson.articleUri != null ? '官方文章與試讀' : '官方雜誌與課程資訊'),
        ),
        if (!available)
          TextButton.icon(
            onPressed: () => _openOfficial(
              _magazine == Magazine.ad
                  ? _magazine.homeUri
                  : Uri.https('m.studioclassroom.com', '/tv-programs.php', {
                      'level': _magazine.code,
                    }),
            ),
            icon: const Icon(Icons.ondemand_video, size: 16),
            label: const Text('官方節目頁'),
          ),
      ],
    );
  }
}

class _MagazineTab extends StatelessWidget {
  const _MagazineTab({
    required this.magazine,
    required this.selected,
    required this.onTap,
  });
  final Magazine magazine;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? const Color(0xff262521) : const Color(0xffEFEDE7),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                magazine.code.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xffDFB5A5)
                      : const Color(0xffB65D43),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  magazine.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xff44413A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.date,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final DateTime date;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? const Color(0xffEFE4DB) : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? const Color(0xffDCC4B5)
                  : const Color(0xffE2DFD7),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? const Color(0xff8B4935)
                      : const Color(0xff77736C),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${date.month}/${date.day}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                const ['週一', '週二', '週三', '週四', '週五', '週六', '週日'][date.weekday -
                    1],
                style: const TextStyle(fontSize: 10, color: Color(0xff77736C)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.retry,
    required this.official,
  });
  final String message;
  final VoidCallback retry;
  final VoidCallback official;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 32),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('重試')),
          TextButton(onPressed: official, child: const Text('前往官方網站')),
        ],
      ),
    ),
  );
}
