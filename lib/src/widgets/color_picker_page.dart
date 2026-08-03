import 'package:flutter/material.dart';

/// Public color picker with 2 tabs: Main / Custom.
/// Returns a Color with `Navigator.pop(context, color)`.
class ColorPickerPage extends StatefulWidget {
  const ColorPickerPage({required this.initial, super.key});

  final Color initial;

  @override
  State<ColorPickerPage> createState() => _ColorPickerPageState();
}

class _ColorPickerPageState extends State<ColorPickerPage>
    with SingleTickerProviderStateMixin {
  late Color _current;

  // 30 mainstream colors (6x5 grid) - Comprehensive palette
  static const List<Color> _main = [
    // Row 1 - Blues and Teals
    Color(0xFF006A6A), // Teal - Primary brand color
    Color(0xFF1E3A8A), // Deep Blue - Professional trust
    Color(0xFF0891B2), // Cyan - Tech and innovation
    Color(0xFF4338CA), // Indigo - Depth and stability
    Color(0xFF0EA5E9), // Sky Blue - Fresh and clean
    // Row 2 - Greens
    Color(0xFF059669), // Emerald Green - Fresh and modern
    Color(0xFF16A34A), // Green - Nature and growth
    Color(0xFF65A30D), // Lime - Energy and vitality
    Color(0xFF84CC16), // Light Lime - Bright and fresh
    Color(0xFF10B981), // Mint - Cool and refreshing
    // Row 3 - Purples and Pinks
    Color(0xFF7C3AED), // Purple - Creative and bold
    Color(0xFF9333EA), // Violet - Luxury and sophistication
    Color(0xFFA855F7), // Light Purple - Soft and elegant
    Color(0xFFDB2777), // Pink - Fun and playful
    Color(0xFFEC4899), // Light Pink - Soft and feminine
    // Row 4 - Reds and Oranges
    Color(0xFFDC2626), // Red - Energy and passion
    Color(0xFFEF4444), // Light Red - Warm and inviting
    Color(0xFFEA580C), // Orange - Warm and vibrant
    Color(0xFFF97316), // Light Orange - Cheerful
    Color(0xFFF59E0B), // Amber - Premium feel
    // Row 5 - Warm and Neutral tones
    Color(0xFFCA8A04), // Gold - Elegant and rich
    Color(0xFFD97706), // Dark Amber - Earthy warmth
    Color(0xFF78716C), // Stone - Neutral and grounded
    Color(0xFF64748B), // Slate - Modern and professional
    Color(0xFF71717A), // Zinc - Industrial chic
    // Row 6 - Deep and Rich colors
    Color(0xFF991B1B), // Dark Red - Bold and dramatic
    Color(0xFF7E22CE), // Deep Purple - Royal and mysterious
    Color(0xFF1D4ED8), // Royal Blue - Classic and trustworthy
    Color(0xFF0D9488), // Dark Teal - Sophisticated
    Color(0xFF166534), // Forest Green - Natural and stable
  ];

  // Custom RGB
  late int _r, _g, _b;
  final _hexCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _r = _to8bit(_current.r);
    _g = _to8bit(_current.g);
    _b = _to8bit(_current.b);
    _hexCtrl.text = _toHex(_current);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  // ---- helpers ----
  int _to8bit(double channel01) => ((channel01 * 255.0).round() & 0xff);

  String _two(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

  String _toHex(Color c) =>
      '#${_two(_to8bit(c.r))}${_two(_to8bit(c.g))}${_two(_to8bit(c.b))}';

  bool _tryParseHex(String s) {
    final v = s.trim();
    final re = RegExp(r'^#?([0-9a-fA-F]{6})$');
    final m = re.firstMatch(v);
    if (m == null) return false;
    final hex = m.group(1)!;
    final r = int.parse(hex.substring(0, 2), radix: 16);
    final g = int.parse(hex.substring(2, 4), radix: 16);
    final b = int.parse(hex.substring(4, 6), radix: 16);
    setState(() {
      _r = r;
      _g = g;
      _b = b;
      _current = Color.fromARGB(0xFF, _r, _g, _b);
      _hexCtrl.text = _toHex(_current);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          // Theme-sensitive: no hardcoded colors here.
          title: const Text('Color picker'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Main'),
              Tab(text: 'Custom'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _current),
              child: const Text('Select'),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // MAIN
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  _PreviewSwatch(color: _current),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1,
                          ),
                      itemCount: _main.length,
                      itemBuilder: (_, i) {
                        final c = _main[i];
                        final sel = c.toARGB32() == _current.toARGB32();
                        return InkWell(
                          onTap: () => setState(() => _current = c),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: sel ? cs.onSurface : Colors.transparent,
                                width: sel ? 2 : 0,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // CUSTOM
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  _PreviewSwatch(color: _current),
                  const SizedBox(height: 12),
                  _RgbSlider(
                    label: 'R',
                    value: _r.toDouble(),
                    active: const Color(0xFFFF0000),
                    digits: (s) => s,
                    onChanged: (v) {
                      setState(() {
                        _r = v.toInt().clamp(0, 255);
                        _current = Color.fromARGB(0xFF, _r, _g, _b);
                        _hexCtrl.text = _toHex(_current);
                      });
                    },
                  ),
                  _RgbSlider(
                    label: 'G',
                    value: _g.toDouble(),
                    active: const Color(0xFF00FF00),
                    digits: (s) => s,
                    onChanged: (v) {
                      setState(() {
                        _g = v.toInt().clamp(0, 255);
                        _current = Color.fromARGB(0xFF, _r, _g, _b);
                        _hexCtrl.text = _toHex(_current);
                      });
                    },
                  ),
                  _RgbSlider(
                    label: 'B',
                    value: _b.toDouble(),
                    active: const Color(0xFF0000FF),
                    digits: (s) => s,
                    onChanged: (v) {
                      setState(() {
                        _b = v.toInt().clamp(0, 255);
                        _current = Color.fromARGB(0xFF, _r, _g, _b);
                        _hexCtrl.text = _toHex(_current);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _hexCtrl,
                    textDirection: TextDirection.ltr, // HEX must be LTR
                    decoration: const InputDecoration(
                      labelText: 'HEX (e.g. #1ABC9C)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (t) {
                      final ok = _tryParseHex(t);
                      if (!ok) {
                        // Snackbar removed - invalid HEX code silently ignored
                        debugPrint('Invalid HEX code: $t');
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSwatch extends StatelessWidget {
  const _PreviewSwatch({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        // Per your preference: avoid withOpacity; use alpha value.
        border: Border.all(color: cs.onSurface.withAlpha((0.30 * 255).round())),
      ),
    );
  }
}

class _RgbSlider extends StatelessWidget {
  const _RgbSlider({
    required this.label,
    required this.value,
    required this.active,
    required this.onChanged,
    required this.digits,
  });

  final String label;
  final double value;
  final Color active;
  final ValueChanged<double> onChanged;
  final String Function(String) digits;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = digits(value.toInt().toString());

    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
        ),
        Expanded(
          child: Slider.adaptive(
            min: 0,
            max: 255,
            divisions: 255,
            value: value.clamp(0, 255).toDouble(),
            onChanged: onChanged,
            activeColor: active,
          ),
        ),
        SizedBox(width: 44, child: Text(shown, textAlign: TextAlign.center)),
      ],
    );
  }
}
