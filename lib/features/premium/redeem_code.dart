import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../app/api.dart';
import '../../app/app_theme.dart';
import '../profile/data/profile_client.dart';
import 'premium_service.dart';

/// "Have a promo code?" — Premium from a code the backend knows (PROMO_CODES):
/// for hackathon judges, press and friends.
///
/// Resolves to the new plan when a code worked, null otherwise.
///
/// **iOS release builds hand over to Apple instead.** App Review guideline
/// 3.1.1 does not allow an app's own codes to unlock features, so there the
/// App Store's offer-code sheet is shown and RevenueCat picks the purchase up
/// like any other. Everywhere else — Android, and every debug or demo build —
/// the code goes to our backend.
Future<PlanInfo?> redeemPromoCode(
  BuildContext context, {
  required ProfileClient client,
  required PremiumService premium,
}) async {
  if (kReleaseMode && defaultTargetPlatform == TargetPlatform.iOS && premium.available) {
    await Purchases.presentCodeRedemptionSheet();
    return null;
  }
  return showDialog<PlanInfo>(
    context: context,
    builder: (_) => _RedeemDialog(client: client),
  );
}

class _RedeemDialog extends StatefulWidget {
  const _RedeemDialog({required this.client});

  final ProfileClient client;

  @override
  State<_RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends State<_RedeemDialog> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final PlanInfo plan = await widget.client.redeem(code);
      if (!mounted) return;
      if (plan.premium) {
        Navigator.of(context).pop(plan);
      } else {
        setState(() {
          _busy = false;
          _error = 'That code did not unlock Premium.';
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Redeem a promo code', style: AppText.section),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            maxLength: 40,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'SHIPATON2026',
              errorText: _error,
              counterText: '',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppText.label.copyWith(color: AppColors.muted)),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _code,
          builder: (BuildContext _, TextEditingValue v, Widget? _) => FilledButton(
            onPressed: v.text.trim().isEmpty || _busy ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7B2FF7)),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Text('Redeem'),
          ),
        ),
      ],
    );
  }
}
