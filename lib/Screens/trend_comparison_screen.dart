import '../Services/e_hospital_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/api_config.dart';
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
  double _thisWeekHR = 0;
  double _lastWeekHR = 0;

  // Gemini AI insights keyed by metric title
  final Map<String, String?> _aiInsights = {};
  bool _aiGenerating = false;


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
      final res = await http.get(Uri.parse("${EHospitalService.baseUrl}/table/wearable_vitals"));
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

      // Exclude 0 values so averages aren't skewed by missing/unrecorded data
      double avg(List<Map<String, dynamic>> list, String key) {
        if (list.isEmpty) return 0;
        final vals = list
            .map((e) => double.tryParse((e[key] ?? "0").toString()) ?? 0.0)
            .where((v) => v > 0)
            .toList();
        if (vals.isEmpty) return 0;
        return vals.reduce((a, b) => a + b) / vals.length;
      }

      if (mounted) {
        setState(() {
          _thisWeekSteps    = avg(thisWeek, "steps");
          _lastWeekSteps    = avg(lastWeek, "steps");
          _thisWeekCalories = avg(thisWeek, "calories");
          _lastWeekCalories = avg(lastWeek, "calories");
          _thisWeekSleep    = avg(thisWeek, "sleep");
          _lastWeekSleep    = avg(lastWeek, "sleep");
          _thisWeekHR       = avg(thisWeek, "heart_rate");
          _lastWeekHR       = avg(lastWeek, "heart_rate");
          _loading = false;
        });
        _generateInsights();
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errorMsg = "Error: $e"; });
    }
  }

  // ── Gemini AI insights ──────────────────────────────────────────────────
  Future<void> _generateInsights() async {
    if (mounted) setState(() { _aiGenerating = true; _aiInsights.clear(); });

    final model = GenerativeModel(
      model: ApiConfig.geminiModel,
      apiKey: ApiConfig.geminiApiKey,
    );

    final prompt = """You are a health assistant. Analyze this patient's week-over-week wearable data and write ONE plain English sentence (max 25 words) for each metric comparing this week to last week. Be specific with numbers.

Steps:         Last week ${_lastWeekSteps.toStringAsFixed(0)} steps/day  → This week ${_thisWeekSteps.toStringAsFixed(0)} steps/day  (goal: 10,000/day)
Active Calories: Last week ${_lastWeekCalories.toStringAsFixed(0)} kcal/day → This week ${_thisWeekCalories.toStringAsFixed(0)} kcal/day  (goal: 300–600/day)
Heart Rate:    Last week ${_lastWeekHR.toStringAsFixed(0)} bpm avg      → This week ${_thisWeekHR.toStringAsFixed(0)} bpm avg      (normal: 60–100 bpm)
Sleep:         Last week ${_lastWeekSleep.toStringAsFixed(1)} hrs/night  → This week ${_thisWeekSleep.toStringAsFixed(1)} hrs/night  (goal: 7–9 hrs)

Reply in this exact format (no extra text):
STEPS: [sentence]
CALORIES: [sentence]
HEART_RATE: [sentence]
SLEEP: [sentence]""";

    try {
      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text ?? "";
      for (final line in text.split('\n')) {
        final t = line.trim();
        if (t.startsWith("STEPS:"))       _aiInsights["Steps"]           = t.replaceFirst("STEPS:", "").trim();
        if (t.startsWith("CALORIES:"))    _aiInsights["Active Calories"]  = t.replaceFirst("CALORIES:", "").trim();
        if (t.startsWith("HEART_RATE:"))  _aiInsights["Heart Rate"]       = t.replaceFirst("HEART_RATE:", "").trim();
        if (t.startsWith("SLEEP:"))       _aiInsights["Sleep"]            = t.replaceFirst("SLEEP:", "").trim();
      }
    } catch (_) {}

    if (mounted) setState(() => _aiGenerating = false);
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
                            description: "Average daily steps this week vs last week. Goal: 10,000 steps/day.",
                            thisWeek: _thisWeekSteps,
                            lastWeek: _lastWeekSteps,
                            unit: "steps",
                            color: Colors.blue,
                            normalMin: 5000,
                            normalMax: 15000,
                          ),
                          const SizedBox(height: 16),
                          _metricCard(
                            icon: Icons.local_fire_department_outlined,
                            title: "Active Calories",
                            description: "Average calories burned per day. Healthy range: 300–600 kcal/day.",
                            thisWeek: _thisWeekCalories,
                            lastWeek: _lastWeekCalories,
                            unit: "kcal",
                            color: Colors.orange,
                            normalMin: 300,
                            normalMax: 600,
                          ),
                          const SizedBox(height: 16),
                          _metricCard(
                            icon: Icons.favorite_border,
                            title: "Heart Rate",
                            description: "Average resting heart rate. Normal range: 60–100 bpm.",
                            thisWeek: _thisWeekHR,
                            lastWeek: _lastWeekHR,
                            unit: "bpm",
                            color: Colors.red,
                            normalMin: 60,
                            normalMax: 100,
                          ),
                          const SizedBox(height: 16),
                          _metricCard(
                            icon: Icons.bedtime_outlined,
                            title: "Sleep",
                            description: "Average hours of sleep per night. Recommended: 7–9 hrs/night.",
                            thisWeek: _thisWeekSleep,
                            lastWeek: _lastWeekSleep,
                            unit: "hrs",
                            color: Color(0xFF6A1B9A),
                            normalMin: 7,
                            normalMax: 9,
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
    required String description,
    required double thisWeek,
    required double lastWeek,
    required String unit,
    required Color color,
    required double normalMin,
    required double normalMax,
  }) {
    final pct     = _pct(thisWeek, lastWeek);
    final pctCol  = _pctColor(thisWeek, lastWeek);
    final pctIcon = _pctIcon(thisWeek, lastWeek);
    final maxVal  = [thisWeek, lastWeek, normalMax * 0.5, 1.0].reduce((a, b) => a > b ? a : b);
    final hasData = thisWeek > 0 || lastWeek > 0;

    // Status of this week's value
    String status; Color statusColor;
    if (thisWeek <= 0) {
      status = "No data this week"; statusColor = Colors.grey;
    } else if (thisWeek < normalMin) {
      status = "Below normal range"; statusColor = Colors.orange;
    } else if (thisWeek > normalMax) {
      status = "Above normal range"; statusColor = Colors.red;
    } else {
      status = "Within normal range"; statusColor = Colors.green;
    }

    // AI-generated interpretation (falls back to loading/empty state)
    final aiText = _aiInsights[title];
    final aiLoading = _aiGenerating && aiText == null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(description,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                Icon(pctIcon, size: 14, color: pctCol),
                const SizedBox(width: 3),
                Text(pct, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pctCol)),
              ]),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(status,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor)),
              ),
            ]),
          ]),

          const SizedBox(height: 16),

          // Bar chart
          SizedBox(
            height: 130,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVal * 1.35,
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      final labels = ["Last Week\n${_fmt(lastWeek)} $unit", "This Week\n${_fmt(thisWeek)} $unit"];
                      if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(labels[idx],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10,
                                color: idx == 1 ? color : AppColors.textMuted,
                                fontWeight: idx == 1 ? FontWeight.w600 : FontWeight.normal)),
                      );
                    },
                    reservedSize: 36,
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
                      toY: lastWeek > 0 ? lastWeek : 0.001,
                      color: color.withOpacity(0.4),
                      width: 44,
                      borderRadius: BorderRadius.circular(8)),
                ]),
                BarChartGroupData(x: 1, barRods: [
                  BarChartRodData(
                      toY: thisWeek > 0 ? thisWeek : 0.001,
                      color: color,
                      width: 44,
                      borderRadius: BorderRadius.circular(8)),
                ]),
              ],
            )),
          ),

          const SizedBox(height: 12),

          // AI-generated interpretation
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(
                    thisWeek <= 0 ? Icons.help_outline
                        : thisWeek >= lastWeek ? Icons.trending_up : Icons.trending_down,
                    size: 14, color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Text("AI Insight", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(5)),
                    child: const Text("Gemini AI", style: TextStyle(fontSize: 8, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 6),
                if (aiLoading)
                  const Row(children: [
                    SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                    SizedBox(width: 8),
                    Text("Generating\u2026", style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ])
                else if (aiText != null && aiText.isNotEmpty)
                  Text(aiText, style: const TextStyle(fontSize: 12, color: AppColors.textDark, height: 1.4))
                else
                  const Text("Sync data to generate insight.", style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
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
