import 'package:flutter/material.dart';
import '../ui/app_theme.dart';

class BmiCalculatorScreen extends StatefulWidget {
  const BmiCalculatorScreen({super.key});

  @override
  State<BmiCalculatorScreen> createState() => _BmiCalculatorScreenState();
}

class _BmiCalculatorScreenState extends State<BmiCalculatorScreen> {
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  double? _bmi;
  String? _category;
  Color? _categoryColor;

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final h = double.tryParse(_heightCtrl.text.trim());
    final w = double.tryParse(_weightCtrl.text.trim());
    if (h == null || w == null || h <= 0 || w <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter valid height and weight")),
      );
      return;
    }
    final hm = h / 100;
    final bmi = w / (hm * hm);
    String cat;
    Color col;
    if (bmi < 18.5) {
      cat = "Underweight";
      col = Colors.blue;
    } else if (bmi < 25) {
      cat = "Normal";
      col = Colors.green;
    } else if (bmi < 30) {
      cat = "Overweight";
      col = Colors.orange;
    } else {
      cat = "Obese";
      col = Colors.red;
    }
    setState(() {
      _bmi = bmi;
      _category = cat;
      _categoryColor = col;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text("BMI Calculator",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.monitor_weight_outlined, size: 48, color: Colors.white54),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Input Card ────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _heightCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Height (cm)",
                            prefixIcon: Icon(Icons.height, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _weightCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Weight (kg)",
                            prefixIcon: Icon(Icons.monitor_weight_outlined, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _calculate,
                            child: const Text("Calculate BMI"),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Result Card ───────────────────────────────
                  if (_bmi != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _categoryColor!.withOpacity(0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(color: _categoryColor!.withOpacity(0.3), width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _bmi!.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.bold,
                              color: _categoryColor,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: _categoryColor!.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _category!,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: _categoryColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _bmiScale(),
                        ],
                      ),
                    ),
                  ],

                  // ── Reference table ───────────────────────────
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("BMI Reference",
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
                        const SizedBox(height: 12),
                        _refRow("< 18.5", "Underweight", Colors.blue),
                        _refRow("18.5 – 24.9", "Normal", Colors.green),
                        _refRow("25.0 – 29.9", "Overweight", Colors.orange),
                        _refRow("≥ 30.0", "Obese", Colors.red),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bmiScale() {
    final ranges = [
      ("Underweight", Colors.blue, 0.0, 18.5),
      ("Normal", Colors.green, 18.5, 25.0),
      ("Overweight", Colors.orange, 25.0, 30.0),
      ("Obese", Colors.red, 30.0, 40.0),
    ];
    final clampedBmi = _bmi!.clamp(10.0, 40.0);
    final position = ((clampedBmi - 10) / 30).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: ranges.map((r) {
              final span = r.$4 - r.$3;
              final flex = (span / 30 * 100).round();
              return Expanded(
                flex: flex,
                child: Container(
                  height: 12,
                  color: r.$2,
                ),
              );
            }).toList(),
          ),
        ),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final indicatorX = (position * constraints.maxWidth).clamp(6.0, constraints.maxWidth - 6.0);
            return Stack(
              children: [
                SizedBox(height: 20, width: constraints.maxWidth),
                Positioned(
                  left: indicatorX - 6,
                  top: 4,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _categoryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _refRow(String range, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(range, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
          Text(label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
