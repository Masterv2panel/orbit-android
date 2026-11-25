// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import 'browser_store.dart';

class BrowserLibraryScreen extends StatefulWidget {
  const BrowserLibraryScreen({super.key, required this.store});

  final BrowserStore store;

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
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک‌کردن')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('کتابخانهٔ مرورگر'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.history), text: 'تاریخچه'),
                Tab(icon: Icon(Icons.bookmark_outline), text: 'نشانک‌ها'),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'history' && await _confirm('پاک‌کردن تاریخچه؟', 'همهٔ بازدیدهای ذخیره‌شده پاک می‌شوند.')) {
                    await _clearHistory();
                  }
                  if (value == 'bookmarks' && await _confirm('پاک‌کردن نشانک‌ها؟', 'همهٔ نشانک‌های ذخیره‌شده پاک می‌شوند.')) {
                    await _clearBookmarks();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'history', child: Text('پاک‌کردن تاریخچه')),
                  PopupMenuItem(value: 'bookmarks', child: Text('پاک‌کردن نشانک‌ها')),
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
              return TabBarView(
                children: [
                  _buildHistory(),
                  _buildBookmarks(),
                ],
              );
            },
          ),
        ),
      );

  Widget _buildHistory() {
    if (_history.isEmpty) return const _EmptyLibrary(text: 'هنوز موردی در تاریخچه نیست.');
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        itemCount: _history.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final visit = _history[index];
          return ListTile(
            leading: const Icon(Icons.history),
            title: Text(visit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${visit.url}\n${_formatTime(visit.visitedAt)}', maxLines: 2, overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr),
            isThreeLine: true,
            onTap: () => Navigator.pop(context, visit.url),
            trailing: IconButton(
              tooltip: 'حذف از تاریخچه',
              icon: const Icon(Icons.close),
              onPressed: () async {
                await widget.store.removeVisit(visit);
                await _refresh();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildBookmarks() {
    if (_bookmarks.isEmpty) return const _EmptyLibrary(text: 'هنوز نشانکی ذخیره نشده است.');
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        itemCount: _bookmarks.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final bookmark = _bookmarks[index];
          return ListTile(
            leading: const Icon(Icons.bookmark),
            title: Text(bookmark.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(bookmark.url, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
            onTap: () => Navigator.pop(context, bookmark.url),
            trailing: IconButton(
              tooltip: 'حذف نشانک',
              icon: const Icon(Icons.bookmark_remove_outlined),
              onPressed: () async {
                await widget.store.removeBookmark(bookmark.url);
                await _refresh();
              },
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final value = dateTime.toLocal();
    final date = '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final time = '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
        ),
      );
}
