import '../Services/e_hospital_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../ui/app_theme.dart';

class HealthGoalsScreen extends StatefulWidget {
  const HealthGoalsScreen({super.key});

  @override
  State<HealthGoalsScreen> createState() => _HealthGoalsScreenState();
}

class _HealthGoalsScreenState extends State<HealthGoalsScreen> {
  bool _loading = true;
  int? _patientId;

  // Goals
  int _goalSteps = 8000;
  double _goalSleep = 8.0;
  int _goalCalories = 500;

  // Actuals from DB
  int _actualSteps = 0;
  double _actualSleep = 0;
  int _actualCalories = 0;


  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawId = prefs.get("patient_id");
    _patientId = int.tryParse(rawId?.toString() ?? '');

    _goalSteps = prefs.getInt("goal_steps_$_patientId") ?? 8000;
    _goalSleep = prefs.getDouble("goal_sleep_$_patientId") ?? 8.0;
    _goalCalories = prefs.getInt("goal_calories_$_patientId") ?? 500;

    if (_patientId != null) await _fetchActuals(_patientId!);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchActuals(int patientId) async {
    try {
      final res = await http.get(Uri.parse("${EHospitalService.baseUrl}/table/wearable_vitals"));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final List<dynamic> raw = decoded is Map ? (decoded['data'] ?? []) : decoded;
        final data = raw.where((e) {
          final id = (e as Map)["patient_id"];
          if (id == null) return false;
          return id is int ? id == patientId : id.toString() == patientId.toString();
        }).toList();

        if (data.isNotEmpty) {
          final latest = data.last;
          _actualSteps = _parseInt(latest["steps"]);
          _actualSleep = _parseDouble(latest["sleep"]);       // API column: "sleep"
          _actualCalories = _parseInt(latest["calories"]);   // API column: "calories"
        }
      }
    } catch (_) {}
  }

  int _parseInt(dynamic v) {
    if (v == null) return 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _saveGoals() async {
    if (_patientId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("goal_steps_$_patientId", _goalSteps);
    await prefs.setDouble("goal_sleep_$_patientId", _goalSleep);
    await prefs.setInt("goal_calories_$_patientId", _goalCalories);
  }

  void _editGoal({
    required String title,
    required String unit,
    required double currentValue,
    required double min,
    required double max,
    required bool isInt,
    required ValueChanged<double> onSave,
  }) {
    double tempVal = currentValue;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Edit $title Goal"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isInt
                    ? "${tempVal.round()} $unit"
                    : "${tempVal.toStringAsFixed(1)} $unit",
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              Slider(
                value: tempVal,
                min: min,
                max: max,
                divisions: isInt ? (max - min).round() : ((max - min) * 2).round(),
                activeColor: AppColors.primary,
                onChanged: (v) => setD(() => tempVal = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onSave(tempVal);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
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
              title: const Text("Health Goals",
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
                  child: Icon(Icons.flag_outlined, size: 48, color: Colors.white54),
                ),
              ),
            ),
          ),
          _loading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()))
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _goalCard(
                        icon: Icons.directions_walk,
                        title: "Daily Steps",
                        actual: _actualSteps.toDouble(),
                        goal: _goalSteps.toDouble(),
                        unit: "steps",
                        color: Colors.blue,
                        onEdit: () => _editGoal(
                          title: "Steps",
                          unit: "steps",
                          currentValue: _goalSteps.toDouble(),
                          min: 1000,
                          max: 30000,
                          isInt: true,
                          onSave: (v) {
                            setState(() => _goalSteps = v.round());
                            _saveGoals();
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      _goalCard(
                        icon: Icons.bedtime_outlined,
                        title: "Sleep",
                        actual: _actualSleep,
                        goal: _goalSleep,
                        unit: "hrs",
                        color: Colors.indigo,
                        onEdit: () => _editGoal(
                          title: "Sleep",
                          unit: "hours",
                          currentValue: _goalSleep,
                          min: 4,
                          max: 12,
                          isInt: false,
                          onSave: (v) {
                            setState(() => _goalSleep = double.parse(v.toStringAsFixed(1)));
                            _saveGoals();
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      _goalCard(
                        icon: Icons.local_fire_department_outlined,
                        title: "Calories Burned",
                        actual: _actualCalories.toDouble(),
                        goal: _goalCalories.toDouble(),
                        unit: "kcal",
                        color: Colors.orange,
                        onEdit: () => _editGoal(
                          title: "Calories",
                          unit: "kcal",
                          currentValue: _goalCalories.toDouble(),
                          min: 100,
                          max: 3000,
                          isInt: true,
                          onSave: (v) {
                            setState(() => _goalCalories = v.round());
                            _saveGoals();
                          },
                        ),
                      ),
                    ]),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _goalCard({
    required IconData icon,
    required String title,
    required double actual,
    required double goal,
    required String unit,
    required Color color,
    required VoidCallback onEdit,
  }) {
    final progress = goal > 0 ? (actual / goal).clamp(0.0, 1.0) : 0.0;
    final pct = (progress * 100).round();
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark)),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                onPressed: onEdit,
                tooltip: "Edit goal",
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                actual == actual.roundToDouble()
                    ? "${actual.round()} / ${goal.round()} $unit"
                    : "${actual.toStringAsFixed(1)} / ${goal.toStringAsFixed(1)} $unit",
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              Text(
                "$pct%",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
