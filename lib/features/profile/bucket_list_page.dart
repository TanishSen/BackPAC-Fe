import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/api.dart';
import '../../app/app_theme.dart';
import '../../app/transitions.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../data/trip_data.dart';
import '../chat/chat_page.dart';
import 'data/profile_client.dart';

/// Places to go one day. Add one, and tap it when "one day" arrives — that
/// opens a conversation already asking to plan it.
class BucketListPage extends StatefulWidget {
  const BucketListPage({super.key, this.client});

  final ProfileClient? client;

  @override
  State<BucketListPage> createState() => _BucketListPageState();
}

class _BucketListPageState extends State<BucketListPage> {
  late final ProfileClient _client = widget.client ?? ProfileClient();
  final TextEditingController _place = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<BucketItem> _items = <BucketItem>[];
  bool _loading = true;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _place.dispose();
    _focus.dispose();
    if (widget.client == null) _client.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<BucketItem> items = await _client.bucketList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _add() async {
    final String place = _place.text.trim();
    if (place.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final BucketItem item = await _client.addToBucketList(place);
      if (!mounted) return;
      _place.clear();
      setState(() {
        _items = <BucketItem>[item, ..._items];
        _adding = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      _toast(e.message);
    }
  }

  Future<void> _remove(BucketItem item) async {
    final List<BucketItem> before = _items;
    setState(() => _items = _items.where((BucketItem i) => i.id != item.id).toList());
    try {
      await _client.removeFromBucketList(item.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _items = before);
      _toast(e.message);
    }
  }

  /// The trip's picture, or a pin for a place the keywords do not know.
  static String _emojiFor(BucketItem item) {
    final String e = tripEmoji(item.place, item.note ?? '', null);
    return e == '💬' ? '📍' : e;
  }

  void _plan(BucketItem item) {
    Navigator.of(context).push(SlideUpRoute<void>(
      page: ChatPage(
        title: item.place,
        opener: 'Plan a trip to ${item.place}',
      ),
    ));
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: AppColors.ink,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 8, AppSpacing.pageH, 0),
              child: Row(
                children: <Widget>[
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Bucket List',
                      style: AppText.title.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 16, AppSpacing.pageH, 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.add_location_alt_outlined, color: AppColors.brand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _place,
                        focusNode: _focus,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _add(),
                        decoration: const InputDecoration(
                          hintText: 'Add a place — Ladakh, Kyoto, Iceland…',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _place,
                      builder: (BuildContext _, TextEditingValue v, Widget? _) => IconButton(
                        tooltip: 'Add',
                        onPressed: v.text.trim().isEmpty || _adding ? null : _add,
                        icon: _adding
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.2),
                              )
                            : const Icon(Icons.arrow_upward_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.brandLine,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_error!, textAlign: TextAlign.center, style: AppText.body),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(32, 40, 32, 0),
        child: Column(
          children: <Widget>[
            Text('🌍', style: TextStyle(fontSize: 40)),
            SizedBox(height: 10),
            Text(
              'Somewhere you have always wanted to go? Add it above, and plan it '
              'whenever you are ready.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pageH,
        4,
        AppSpacing.pageH,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: _items.length,
      itemBuilder: (BuildContext _, int i) {
        final BucketItem item = _items[i];
        return Dismissible(
          key: ValueKey<int>(item.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _remove(item),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFDECEA),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFC0392B)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                leading: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandSoft, width: 2),
                  ),
                  child: Text(_emojiFor(item), style: const TextStyle(fontSize: 20)),
                ),
                title: Text(item.place, style: AppText.cardTitle),
                subtitle: item.note == null ? null : Text(item.note!, style: AppText.caption),
                trailing: TextButton(
                  onPressed: () => _plan(item),
                  style: TextButton.styleFrom(foregroundColor: AppColors.brand),
                  child: const Text('Plan it', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                onTap: () => _plan(item),
              ),
            ),
          ),
        );
      },
    );
  }
}
