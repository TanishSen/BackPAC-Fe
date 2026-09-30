import 'package:flutter/material.dart';

import '../../app/api.dart';
import '../../app/app_theme.dart';
import 'data/profile_client.dart';

/// "Edit Profile": an avatar, a name, a home city and a line about yourself.
///
/// Pops with the updated [Me] when saved, or nothing when dismissed. Only the
/// fields that changed are sent; a field emptied is sent as "" and cleared.
class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({
    super.key,
    required this.client,
    required this.profile,
    this.fallbackName,
  });

  final ProfileClient client;
  final Profile profile;

  /// The sign-up name, shown as the hint when no display name is set.
  final String? fallbackName;

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.displayName ?? '');
  late final TextEditingController _city =
      TextEditingController(text: widget.profile.homeCity ?? '');
  late final TextEditingController _bio =
      TextEditingController(text: widget.profile.bio ?? '');
  late String? _avatar = widget.profile.avatar;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// "" for a field that was set and is now empty, the new text for one that
  /// changed, and null (not sent) for one left alone.
  static String? _changed(String? before, String now) {
    final String clean = now.trim();
    if (clean == (before ?? '')) return null;
    return clean;
  }

  Future<void> _save() async {
    final String? name = _changed(widget.profile.displayName, _name.text);
    final String? city = _changed(widget.profile.homeCity, _city.text);
    final String? bio = _changed(widget.profile.bio, _bio.text);
    final String? avatar = _avatar == widget.profile.avatar ? null : (_avatar ?? '');
    if (name == null && city == null && bio == null && avatar == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Me me = await widget.client.update(
        displayName: name,
        homeCity: city,
        bio: bio,
        avatar: avatar,
      );
      if (mounted) Navigator.of(context).pop(me);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Edit profile', style: AppText.section),
              const SizedBox(height: 14),
              const Text('Avatar', style: AppText.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final String a in kAvatars)
                    Semantics(
                      button: true,
                      selected: a == _avatar,
                      label: 'Avatar $a',
                      child: GestureDetector(
                        onTap: () => setState(() => _avatar = a == _avatar ? null : a),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: a == _avatar ? AppColors.brandWash : AppColors.canvas,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: a == _avatar ? AppColors.brand : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Text(a, style: const TextStyle(fontSize: 24)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _Field(
                controller: _name,
                label: 'Name',
                hint: widget.fallbackName ?? 'What should we call you?',
                maxLength: 60,
              ),
              _Field(
                controller: _city,
                label: 'Home city',
                hint: 'Kolkata, India',
                maxLength: 80,
                icon: Icons.location_on_outlined,
              ),
              _Field(
                controller: _bio,
                label: 'About you',
                hint: 'Collecting moments, not things ✨',
                maxLength: 160,
                lines: 2,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: AppText.body.copyWith(color: const Color(0xFFC0392B))),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: const StadiumBorder(),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.maxLength,
    this.lines = 1,
    this.icon,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLength;
  final int lines;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        minLines: lines,
        maxLines: lines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          filled: true,
          fillColor: AppColors.canvas,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
