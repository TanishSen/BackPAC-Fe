/// Signing in and signing up — one screen, two modes.
///
/// One screen rather than two, because they are the same form with one extra
/// field and a different verb. Two screens means two layouts to keep in step,
/// and a "no account? register" link that throws away everything the person
/// already typed. Here, switching modes keeps the email they entered.
///
/// The look follows the app rather than the reference: the orb is the brand,
/// not a photograph, so it takes the top of the screen and the form sits on a
/// sheet below it — the same sheet shape, corner radius and pill button the
/// rest of the app uses.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../orb/rezolve_orb.dart';
import 'data/auth_service.dart';
import 'widgets/auth_field.dart';
import 'widgets/submit_button.dart';

enum AuthMode { login, register }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.mode = AuthMode.login, this.onSignedIn});

  final AuthMode mode;

  /// Called once sign-in succeeds. The app decides where to go next; this
  /// screen's only job is to get a session.
  final VoidCallback? onSignedIn;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late AuthMode _mode = widget.mode;
  final AuthService _auth = AuthService();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _busy = false;

  /// Per-field complaints, and one for the whole form when the server refuses.
  String? _emailError;
  String? _passwordError;
  String? _formError;

  /// Shown after signing up when Supabase wants the address confirmed first.
  String? _notice;

  bool get _isLogin => _mode == AuthMode.login;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _mode = _isLogin ? AuthMode.register : AuthMode.login;
      // Keep the email — retyping it is the most annoying part of realising
      // you were on the wrong screen. Clear the errors, which belonged to the
      // other mode's attempt.
      _emailError = null;
      _passwordError = null;
      _formError = null;
      _notice = null;
    });
  }

  /// Check what we can without asking the server.
  ///
  /// Not to be clever about it — a regex cannot tell you an address exists —
  /// but a round trip to find out you left a field blank is a second of
  /// someone's life for nothing.
  bool _validate() {
    final String email = _email.text.trim();
    final String password = _password.text;

    String? emailError;
    String? passwordError;

    if (email.isEmpty) {
      emailError = 'Enter your email address.';
    } else if (!email.contains('@') || !email.contains('.')) {
      emailError = 'That does not look like an email address.';
    }

    if (password.isEmpty) {
      passwordError = 'Enter your password.';
    } else if (!_isLogin && password.length < 6) {
      // Only on the way in. Telling someone their existing password is too
      // short when they are trying to log in with it is both wrong and
      // useless.
      passwordError = 'Use at least 6 characters.';
    }

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _formError = null;
    });
    return emailError == null && passwordError == null;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _notice = null;
    });

    final String? error = _isLogin
        ? await _auth.signIn(
            email: _email.text, password: _password.text)
        : await _auth.signUp(
            email: _email.text,
            password: _password.text,
            displayName: _name.text,
          );

    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      setState(() => _formError = error);
      return;
    }

    if (_auth.isSignedIn) {
      widget.onSignedIn?.call();
      return;
    }

    // Signed up, but no session: email confirmation is on. Say so rather than
    // sit there looking like nothing happened.
    setState(() {
      _mode = AuthMode.login;
      _password.clear();
      _notice =
          'Account created. Check ${_email.text.trim()} for a confirmation '
          'link, then log in.';
    });
  }

  Future<void> _forgotPassword() async {
    final String email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Enter your email first, then tap this.');
      return;
    }
    setState(() => _busy = true);
    final String? error = await _auth.sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _formError = error;
      // Said the same way whether or not the address is registered. "No such
      // account" would let anyone check which emails have signed up here.
      _notice = error == null
          ? 'If there is an account for $email, a reset link is on its way.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    // Cap the scale rather than let very large system text collide the orb
    // with the form — the same treatment the welcome screen gives it.
    final TextScaler scaler = media.textScaler.clamp(maxScaleFactor: 1.3);
    // Shrink the orb when the keyboard is up, so the field being typed into
    // stays on screen instead of being pushed under it.
    final bool keyboard = media.viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      resizeToAvoidBottomInset: true,
      body: MediaQuery(
        data: media.copyWith(textScaler: scaler),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                height: keyboard ? 96 : 188,
                alignment: Alignment.center,
                child: RezolveOrb(
                  size: keyboard ? 78 : 150,
                  // Paused while typing: an orb breathing away next to a form
                  // is a moving thing beside the one thing you want someone
                  // concentrating on, and it costs a repaint every frame.
                  paused: keyboard,
                  mood: OrbMood.idle,
                ),
              ),
              Expanded(child: _sheet()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheet() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pageH,
          30,
          AppSpacing.pageH,
          // Clear the keyboard when it is up, the home indicator when it is not.
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.bottomSafe,
        ),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _isLogin ? 'Welcome back' : 'Let’s get you started',
                style: AppText.title,
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin
                    ? 'Log in to pick up your plans where you left them.'
                    : 'Create an account and your trips stay with you, on any '
                        'phone.',
                style: AppText.body,
              ),
              const SizedBox(height: 26),

              if (!_isLogin) ...<Widget>[
                AuthField(
                  label: 'Your name',
                  hint: 'What should it call you?',
                  controller: _name,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.name],
                ),
                const SizedBox(height: 18),
              ],

              AuthField(
                label: 'Email',
                hint: 'you@example.com',
                controller: _email,
                enabled: !_busy,
                error: _emailError,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.email],
              ),
              const SizedBox(height: 18),

              AuthField(
                label: 'Password',
                hint: _isLogin ? null : 'At least 6 characters',
                controller: _password,
                enabled: !_busy,
                error: _passwordError,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: <String>[
                  _isLogin
                      ? AutofillHints.password
                      : AutofillHints.newPassword,
                ],
                onSubmitted: (_) => _submit(),
              ),

              if (_isLogin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: AppText.label.copyWith(color: AppColors.brand),
                    ),
                  ),
                ),

              if (_formError != null) _banner(_formError!, bad: true),
              if (_notice != null) _banner(_notice!, bad: false),

              SizedBox(height: _isLogin ? 14 : 28),
              SubmitButton(
                label: _isLogin ? 'Log in' : 'Create account',
                busy: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 22),

              Center(
                child: GestureDetector(
                  onTap: _busy ? null : _switchMode,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text.rich(
                      TextSpan(
                        style: AppText.body,
                        children: <TextSpan>[
                          TextSpan(
                            text: _isLogin
                                ? 'Don’t have an account? '
                                : 'Already have one? ',
                          ),
                          TextSpan(
                            text: _isLogin ? 'Register here' : 'Log in',
                            style: AppText.body.copyWith(
                              color: AppColors.brand,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A message about the whole form, rather than one field.
  Widget _banner(String text, {required bool bad}) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: bad ? const Color(0xFFFDECEA) : AppColors.brandWash,
          borderRadius: BorderRadius.circular(AppSpacing.bubbleRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              bad ? Icons.error_outline : Icons.mark_email_unread_outlined,
              size: 18,
              color: bad ? const Color(0xFFC0392B) : AppColors.brand,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: AppText.caption.copyWith(
                  height: 1.45,
                  color: bad ? const Color(0xFFC0392B) : AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
