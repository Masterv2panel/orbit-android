// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import 'browser_store.dart';
import 'orbit_localization.dart';

class BrowserLibraryScreen extends StatefulWidget {
  const BrowserLibraryScreen({
    super.key,
    required this.store,
    this.onToggleLocale,
  });

  final BrowserStore store;
  final VoidCallback? onToggleLocale;

  @override
  State<BrowserLibraryScreen> createState() => _BrowserLibraryScreenState();
}

class _BrowserLibraryScreenState extends State<BrowserLibraryScreen> {
  late Future<void> _loading;
  List<BrowserVisit> _history = [];
  List<BrowserBookmark> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _loading = _refresh();
  }

  Future<void> _refresh() async {
    final history = await widget.store.loadHistory();
    final bookmarks = await widget.store.loadBookmarks();
    if (!mounted) return;
    setState(() {
      _history = history;
      _bookmarks = bookmarks;
    });
  }

  Future<void> _clearHistory() async {
    await widget.store.clearHistory();
    await _refresh();
  }

  Future<void> _clearBookmarks() async {
    await widget.store.clearBookmarks();
    await _refresh();
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(orbitText(context, 'انصراف')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(orbitText(context, 'پاک‌کردن')),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          orbitText(context, 'کتابخانهٔ مرورگر'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          indicatorColor: const Color(0xFF52E6DF),
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          unselectedLabelColor: const Color(0xFF929FB1),
          tabs: [
            Tab(
              icon: const Icon(Icons.history),
              text: orbitText(context, 'تاریخچه'),
            ),
            Tab(
              icon: const Icon(Icons.bookmark_outline),
              text: orbitText(context, 'نشانک‌ها'),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: orbitText(context, 'تغییر زبان'),
            onPressed: widget.onToggleLocale,
            icon: Text(
              Localizations.localeOf(context).languageCode == 'en'
                  ? 'FA'
                  : 'EN',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'history' &&
                  await _confirm(
                    orbitText(context, 'پاک‌کردن تاریخچه؟'),
                    orbitText(context, 'همهٔ بازدیدهای ذخیره‌شده پاک می‌شوند.'),
                  )) {
                await _clearHistory();
              }
              if (value == 'bookmarks' &&
                  await _confirm(
                    orbitText(context, 'پاک‌کردن نشانک‌ها؟'),
                    orbitText(context, 'همهٔ نشانک‌های ذخیره‌شده پاک می‌شوند.'),
                  )) {
                await _clearBookmarks();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'history',
                child: Text(orbitText(context, 'پاک‌کردن تاریخچه')),
              ),
              PopupMenuItem(
                value: 'bookmarks',
                child: Text(orbitText(context, 'پاک‌کردن نشانک‌ها')),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(children: [_buildHistory(), _buildBookmarks()]);
        },
      ),
    ),
  );

  Widget _buildHistory() {
    if (_history.isEmpty)
      return _EmptyLibrary(
        text: orbitText(context, 'هنوز موردی در تاریخچه نیست.'),
        icon: Icons.history_rounded,
      );
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        itemCount: _history.length,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        separatorBuilder: (_, __) => const SizedBox(height: 9),
        itemBuilder: (context, index) {
          final visit = _history[index];
          return Card(
            margin: EdgeInsets.zero,
            color: const Color(0xFF111A27),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF29384A)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              minLeadingWidth: 42,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 7,
              ),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1A2B3A),
                child: Icon(Icons.history, color: Color(0xFF52E6DF)),
              ),
              title: Text(
                visit.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${visit.url}\n${_formatTime(visit.visitedAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
              ),
              isThreeLine: true,
              onTap: () => Navigator.pop(context, visit.url),
              trailing: IconButton(
                tooltip: orbitText(context, 'حذف از تاریخچه'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close),
                onPressed: () async {
                  await widget.store.removeVisit(visit);
                  await _refresh();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBookmarks() {
    if (_bookmarks.isEmpty)
      return _EmptyLibrary(
        text: orbitText(context, 'هنوز نشانکی ذخیره نشده است.'),
        icon: Icons.bookmark_border_rounded,
      );
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        itemCount: _bookmarks.length,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        separatorBuilder: (_, __) => const SizedBox(height: 9),
        itemBuilder: (context, index) {
          final bookmark = _bookmarks[index];
          return Card(
            margin: EdgeInsets.zero,
            color: const Color(0xFF111A27),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF29384A)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              minLeadingWidth: 42,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 7,
              ),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1A2B3A),
                child: Icon(Icons.bookmark, color: Color(0xFF52E6DF)),
              ),
              title: Text(
                bookmark.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                bookmark.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
              ),
              onTap: () => Navigator.pop(context, bookmark.url),
              trailing: IconButton(
                tooltip: orbitText(context, 'حذف نشانک'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.bookmark_remove_outlined),
                onPressed: () async {
                  await widget.store.removeBookmark(bookmark.url);
                  await _refresh();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final value = dateTime.toLocal();
    final date =
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final time =
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: BoxDecoration(
          color: const Color(0xFF111A27),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF29384A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF52E6DF)),
            const SizedBox(height: 14),
            Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: const Color(0xFFBECADB), height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
