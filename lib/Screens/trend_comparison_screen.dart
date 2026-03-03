import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import '../ui/app_theme.dart';

class TrendComparisonScreen extends StatefulWidget {
  const TrendComparisonScreen({super.key});

  @override
  State<TrendComparisonScreen> createState() => _TrendComparisonScreenState();
}

class _TrendComparisonScreenState extends State<TrendComparisonScreen> {
  bool _loading = true;
  String? _errorMsg;

  double _thisWeekSteps = 0;
  double _lastWeekSteps = 0;
  double _thisWeekCalories = 0;
  double _lastWeekCalories = 0;
  double _thisWeekSleep = 0;
  double _lastWeekSleep = 0;

  static const String _baseUrl =
      "https://aetab8pjmb.us-east-1.awsapprunner.com/table";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawId = prefs.get("patient_id");
    if (rawId == null) {
      if (mounted) setState(() { _loading = false; _errorMsg = "Not logged in"; });
      return;
    }
    final patientId = int.tryParse(rawId.toString());
    if (patientId == null) {
      if (mounted) setState(() { _loading = false; _errorMsg = "Invalid patient ID"; });
      return;
    }

    try {
      final res = await http.get(Uri.parse("$_baseUrl/wearable_vitals"));
      if (res.statusCode != 200) {
        if (mounted) setState(() { _loading = false; _errorMsg = "Failed to load data"; });
        return;
      }
      final decoded = jsonDecode(res.body);
      final List<dynamic> all = decoded is Map ? (decoded['data'] ?? []) : decoded;
      final records = all.where((e) {
        final id = e["patient_id"];
        if (id == null) return false;
        return id is int ? id == patientId : id.toString() == patientId.toString();
      }).toList();

      final now = DateTime.now();
      final thisMonday = now.subtract(Duration(days: now.weekday - 1));
      final lastMonday = thisMonday.subtract(const Duration(days: 7));
      final lastSunday = thisMonday.subtract(const Duration(days: 1));

      final thisWeek = <Map<String, dynamic>>[];
      final lastWeek = <Map<String, dynamic>>[];

      for (final r in records) {
        final dateStr = r["date"] as String? ?? r["timestamp"] as String? ?? "";
        if (dateStr.isEmpty) continue;
        try {
          final dt = DateTime.parse(dateStr);
          if (!dt.isBefore(thisMonday)) {
            thisWeek.add(Map<String, dynamic>.from(r));
          } else if (!dt.isBefore(lastMonday) && !dt.isAfter(lastSunday)) {
            lastWeek.add(Map<String, dynamic>.from(r));
          }
        } catch (_) {}
      }

      double avg(List<Map<String, dynamic>> list, String key) {
        if (list.isEmpty) return 0;
        final vals = list.map((e) => double.tryParse((e[key] ?? "0").toString()) ?? 0.0).toList();
        return vals.reduce((a, b) => a + b) / vals.length;
      }

      if (mounted) {
        setState(() {
          _thisWeekSteps = avg(thisWeek, "steps");
          _lastWeekSteps = avg(lastWeek, "steps");
          // API stores "calories" (not "calories_burned") and "sleep" (not "sleep_hours")
          _thisWeekCalories = avg(thisWeek, "calories");
          _lastWeekCalories = avg(lastWeek, "calories");
          _thisWeekSleep = avg(thisWeek, "sleep");
          _lastWeekSleep = avg(lastWeek, "sleep");
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errorMsg = "Error: $e"; });
    }
  }

  String _pct(double thisW, double lastW) {
    if (lastW == 0) return thisW > 0 ? "+∞%" : "—";
    final p = ((thisW - lastW) / lastW * 100);
    return "${p >= 0 ? "+" : ""}${p.toStringAsFixed(1)}%";
  }

  Color _pctColor(double thisW, double lastW) {
    if (lastW == 0) return AppColors.textMuted;
    return thisW >= lastW ? Colors.green : Colors.red;
  }

  IconData _pctIcon(double thisW, double lastW) {
    if (lastW == 0) return Icons.remove;
    return thisW >= lastW ? Icons.arrow_upward : Icons.arrow_downward;
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
              title: const Text("Trend Analysis",
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
                  child: Icon(Icons.trending_up, size: 48, color: Colors.white54),
                ),
              ),
            ),
          ),
          _loading
              ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              : _errorMsg != null
                  ? SliverFillRemaining(
                      child: Center(
                        child: Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // Legend
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _legendDot(Colors.blue.shade300, "Last Week"),
                              const SizedBox(width: 20),
                              _legendDot(AppColors.primary, "This Week"),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _metricCard(
                            icon: Icons.directions_walk,
                            title: "Steps",
                            thisWeek: _thisWeekSteps,
                            lastWeek: _lastWeekSteps,
                            unit: "steps",
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 16),
                          _metricCard(
                            icon: Icons.local_fire_department_outlined,
                            title: "Calories Burned",
                            thisWeek: _thisWeekCalories,
                            lastWeek: _lastWeekCalories,
                            unit: "kcal",
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 16),
                          _metricCard(
                            icon: Icons.bedtime_outlined,
                            title: "Sleep",
                            thisWeek: _thisWeekSleep,
                            lastWeek: _lastWeekSleep,
                            unit: "hrs",
                            color: Colors.indigo,
                          ),
                        ]),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String title,
    required double thisWeek,
    required double lastWeek,
    required String unit,
    required Color color,
  }) {
    final pct = _pct(thisWeek, lastWeek);
    final pctCol = _pctColor(thisWeek, lastWeek);
    final pctIcon = _pctIcon(thisWeek, lastWeek);

    final maxVal = [thisWeek, lastWeek, 1.0].reduce((a, b) => a > b ? a : b);

    return Container(
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              ),
              Icon(pctIcon, size: 16, color: pctCol),
              const SizedBox(width: 4),
              Text(pct, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pctCol)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.3,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final labels = ["Last Week", "This Week"];
                        final idx = value.toInt();
                        if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(labels[idx],
                              style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        );
                      },
                      reservedSize: 28,
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(
                        toY: lastWeek,
                        color: color.withOpacity(0.45),
                        width: 40,
                        borderRadius: BorderRadius.circular(8)),
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                        toY: thisWeek,
                        color: color,
                        width: 40,
                        borderRadius: BorderRadius.circular(8)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Last: ${_fmt(lastWeek)} $unit",
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              Text("This: ${_fmt(thisWeek)} $unit",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }
}
