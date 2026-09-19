import 'dart:async';

import 'package:flutter/material.dart';

import 'rezolve_orb.dart';

/// A page you can push to see every mood, and to feel the pacing before wiring
/// the orb into a real conversation. Delete it once you're happy.
class OrbDemoPage extends StatefulWidget {
  const OrbDemoPage({super.key});

  @override
  State<OrbDemoPage> createState() => _OrbDemoPageState();
}

class _OrbDemoPageState extends State<OrbDemoPage> {
  OrbMood _mood = OrbMood.idle;
  double _size = 240;
  Timer? _script;

  static const Map<OrbMood, String> _captions = <OrbMood, String>{
    OrbMood.idle: 'Waiting for you.',
    OrbMood.listening: 'Listening…',
    OrbMood.thinking: 'Thinking it through…',
    OrbMood.speaking: 'Here is what I found.',
  };

  @override
  void dispose() {
    _script?.cancel();
    super.dispose();
  }

  /// Runs the sequence a real turn takes: listen, think, answer, settle.
  void _playTurn() {
    _script?.cancel();
    setState(() => _mood = OrbMood.listening);
    _script = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _mood = OrbMood.thinking);
      _script = Timer(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        setState(() => _mood = OrbMood.speaking);
        _script = Timer(const Duration(milliseconds: 6000), () {
          if (!mounted) return;
          setState(() => _mood = OrbMood.idle);
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Spacer(flex: 3),
            RezolveOrb(size: _size, mood: _mood),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Text(
                _captions[_mood]!,
                key: ValueKey<OrbMood>(_mood),
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  letterSpacing: 0.1,
                  color: Color(0xFF5B6170),
                ),
              ),
            ),
            const Spacer(flex: 2),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final OrbMood m in OrbMood.values)
                  ChoiceChip(
                    label: Text(m.name),
                    selected: _mood == m,
                    onSelected: (_) {
                      _script?.cancel();
                      setState(() => _mood = m);
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('play a turn'),
                  onPressed: _playTurn,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: <Widget>[
                  const Text('size', style: TextStyle(color: Color(0xFF5B6170))),
                  Expanded(
                    child: Slider(
                      value: _size,
                      min: 64,
                      max: 320,
                      onChanged: (double v) => setState(() => _size = v),
                    ),
                  ),
                  Text('${_size.round()}',
                      style: const TextStyle(color: Color(0xFF5B6170))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
