
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:health/health.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../services/e_hospital_service.dart';
import '../config/api_config.dart';
import '../ui/app_theme.dart';

class VitalsScreen extends StatefulWidget {
  const VitalsScreen({super.key});

  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  List<FlSpot> stepSpots = [];
  List<FlSpot> calorieSpots = [];
  List<FlSpot> heartRateSpots = [];
  List<FlSpot> sleepSpots = [];
  List<String> timeLabels = [];
  bool isLoading = true;
  int selectedIndex = 0;
  String currentPatientId = "";
  List<dynamic> _rawFilteredData = [];
  int _rangeDays = 7; // 7, 14, 30, 0 = All
  String? _ecgResult;
  double _liveBaselineHR = 72.0;
  String _liveBaselineBP = "120/80";
  bool _hasZeroHR = false;

  // Apple Health sync state
  bool _syncingAppleHealth = false;
  String? _lastSyncStatus;
  int _wearableRecordCount = 0;

  // Gemini AI summaries — keyed by tab index (0=Steps,1=Cal,2=HR,3=Sleep)
  final Map<int, String?> _aiSummaries = {};
  bool _aiGenerating = false;

  String get _clinicalECG => _ecgResult ?? "Unknown";

  static const _tabs = [
    _TabItem(icon: Icons.directions_walk, label: "Steps", color: Colors.blue),
    _TabItem(icon: Icons.local_fire_department, label: "Calories", color: Colors.orange),
    _TabItem(icon: Icons.favorite_border, label: "Heart Rate", color: Colors.red),
    _TabItem(icon: Icons.bedtime_outlined, label: "Sleep", color: Color(0xFF6A1B9A)),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    // Use prefs.get() to handle patient_id stored as either int or String
    final Object? rawId = prefs.get("patient_id");
    final String searchId = rawId?.toString() ?? "";

    String? ecgResult;
    try {
      final ecgRes = await http.get(Uri.parse(
          "${EHospitalService.baseUrl}/table/ecg"));
      if (ecgRes.statusCode == 200) {
        final ecgList = (jsonDecode(ecgRes.body)["data"] as List<dynamic>? ?? [])
            .where((e) => e["patient_id"].toString() == searchId)
            .toList();
        if (ecgList.isNotEmpty) {
          ecgList.sort((a, b) => (b["recorded_on"] ?? "").compareTo(a["recorded_on"] ?? ""));
          ecgResult = ecgList.first["ecg_result"]?.toString();
        }
      }
    } catch (_) {}

    double liveHR = 72.0;
    String liveBP = "120/80";
    try {
      final vhRes = await http.get(Uri.parse(
          "${EHospitalService.baseUrl}/table/vitals_history?patient_id=$searchId"));
      if (vhRes.statusCode == 200) {
        final vhList = (jsonDecode(vhRes.body)["data"] as List<dynamic>? ?? [])
            .where((e) => e["patient_id"].toString() == searchId)
            .toList();
        if (vhList.isNotEmpty) {
          vhList.sort((a, b) => (b["recorded_on"] ?? "").toString().compareTo((a["recorded_on"] ?? "").toString()));
          final latest = vhList.first;
          final hrVal = latest["heart_rate"];
          final bpVal = latest["blood_pressure"];
          if (hrVal != null) liveHR = (hrVal is num) ? hrVal.toDouble() : double.tryParse(hrVal.toString()) ?? 72.0;
          if (bpVal != null && bpVal.toString().isNotEmpty) liveBP = bpVal.toString();
        }
      }
    } catch (_) {}

    final List<dynamic> rawData = await EHospitalService.fetchVitals();
    final filteredData = rawData
        .where((item) => item['patient_id'].toString() == searchId)
        .toList();
    filteredData.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));

    if (mounted) {
      setState(() {
        currentPatientId = searchId;
        _ecgResult = ecgResult;
        _liveBaselineHR = liveHR;
        _liveBaselineBP = liveBP;
        _rawFilteredData = filteredData;
        isLoading = false;
      });
      _applyRange(triggerAI: true);
    }
  }

  void _applyRange({bool triggerAI = false}) {
    final now = DateTime.now();
    final cutoff = _rangeDays > 0
        ? now.subtract(Duration(days: _rangeDays))
        : DateTime(2000);

    final ranged = _rawFilteredData.where((d) {
      try {
        return DateTime.parse(d['timestamp'].toString()).isAfter(cutoff);
      } catch (_) {
        return true;
      }
    }).toList();

    List<FlSpot> sSpots = [], cSpots = [], hrSpots = [], slSpots = [];
    List<String> labels = [];
    bool hasZero = false;

    for (int i = 0; i < ranged.length; i++) {
      final d = ranged[i];
      final s = double.tryParse(d['steps'].toString()) ?? 0.0;
      final c = double.tryParse(d['calories'].toString()) ?? 0.0;
      final hr = double.tryParse(d['heart_rate'].toString()) ?? 0.0;
      final sl = double.tryParse(d['sleep'].toString()) ?? 0.0;
      if (hr == 0.0) hasZero = true;
      sSpots.add(FlSpot(i.toDouble(), s));
      cSpots.add(FlSpot(i.toDouble(), c));
      hrSpots.add(FlSpot(i.toDouble(), hr));
      slSpots.add(FlSpot(i.toDouble(), sl));
      labels.add(DateFormat('MM/dd HH:mm').format(DateTime.parse(d['timestamp']).toLocal()));
    }

    if (mounted) {
      setState(() {
        stepSpots = sSpots;
        calorieSpots = cSpots;
        heartRateSpots = hrSpots;
        sleepSpots = slSpots;
        timeLabels = labels;
        _hasZeroHR = hasZero;
        _wearableRecordCount = ranged.length;
        if (triggerAI) { _aiSummaries.clear(); _aiGenerating = false; }
      });
      if (triggerAI) _generateAllSummaries();
    }
  }

  // ── Gemini AI summaries ──────────────────────────────────────────────────
  Future<void> _generateAllSummaries() async {
    if (mounted) setState(() { _aiGenerating = true; _aiSummaries.clear(); });

    const tabNames     = ["Steps", "Active Calories", "Heart Rate", "Sleep"];
    const units        = ["steps", "kcal", "bpm", "hrs"];
    const normalRanges = ["5,000–15,000 steps/day", "300–600 kcal/day",
                          "60–100 bpm", "7–9 hrs/night"];

    final allSpots = [stepSpots, calorieSpots, heartRateSpots, sleepSpots];

    final model = GenerativeModel(
      model: ApiConfig.geminiModel,
      apiKey: ApiConfig.geminiApiKey,
    );

    for (int i = 0; i < 4; i++) {
      final spots   = allSpots[i];
      final nonZero = spots.map((s) => s.y).where((v) => v > 0).toList();
      final latest  = spots.isNotEmpty ? spots.last.y : 0.0;
      final avg     = nonZero.isNotEmpty
          ? nonZero.reduce((a, b) => a + b) / nonZero.length
          : 0.0;
      final max     = nonZero.isNotEmpty
          ? nonZero.reduce((a, b) => a > b ? a : b)
          : 0.0;
      final zeroCount = spots.length - nonZero.length;
      final hrNote    = i == 2 && _liveBaselineHR > 0
          ? "\n- Clinical baseline HR from hospital records: ${_liveBaselineHR.toInt()} bpm"
          : "";

      final prompt = nonZero.isEmpty
          ? "A patient has no ${tabNames[i]} data from their wearable device. "
            "Write 1 short plain English sentence for a health dashboard telling them to sync their device."
          : "Patient wearable data — ${tabNames[i]}:\n"
            "- Latest reading: ${latest.toStringAsFixed(1)} ${units[i]}\n"
            "- Average (non-zero readings only): ${avg.toStringAsFixed(1)} ${units[i]}\n"
            "- Peak recorded: ${max.toStringAsFixed(1)} ${units[i]}\n"
            "- Readings with no data: $zeroCount out of ${spots.length} total$hrNote\n"
            "- Healthy range: ${normalRanges[i]}\n\n"
            "Write 2–3 plain English sentences for a patient health dashboard. "
            "Be specific with the numbers. Note if the value is healthy, improving, or needs attention. "
            "Do not suggest specific medications. Keep it under 70 words.";

      try {
        final response = await model.generateContent([Content.text(prompt)]);
        if (mounted) setState(() => _aiSummaries[i] = response.text?.trim() ?? "");
      } catch (_) {
        if (mounted) setState(() => _aiSummaries[i] = "Unable to generate insight for ${tabNames[i]}.");
      }
    }

    if (mounted) setState(() => _aiGenerating = false);
  }

  // ── Apple Watch / Apple Health Sync ─────────────────────────────────────
  Future<void> _syncFromAppleHealth() async {
    setState(() { _syncingAppleHealth = true; _lastSyncStatus = null; });

    try {
      final health = Health();

      // health package v13+ requires configure() before any other calls
      await health.configure();

      // Data types we want from Apple Health (sourced from Apple Watch)
      const types = [
        HealthDataType.STEPS,
        HealthDataType.HEART_RATE,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.SLEEP_ASLEEP,
      ];

      // Request permission
      final permissions = types.map((_) => HealthDataAccess.READ).toList();
      final granted = await health.requestAuthorization(types, permissions: permissions);

      if (!granted) {
        setState(() {
          _syncingAppleHealth = false;
          _lastSyncStatus = "Permission denied. Enable Health access in Settings → Privacy → Health.";
        });
        return;
      }

      // Fetch last 24 hours of data
      final now = DateTime.now();
      final since = now.subtract(const Duration(hours: 24));

      final dataPoints = await health.getHealthDataFromTypes(
        startTime: since,
        endTime: now,
        types: types,
      );

      // Deduplicate
      final unique = health.removeDuplicates(dataPoints);

      // Aggregate into single snapshot
      int steps = 0;
      double totalHR = 0;
      int hrCount = 0;
      double calories = 0;
      double sleepMinutes = 0;

      for (final point in unique) {
        final value = point.value;
        switch (point.type) {
          case HealthDataType.STEPS:
            if (value is NumericHealthValue) {
              steps += value.numericValue.round();
            }
            break;
          case HealthDataType.HEART_RATE:
            if (value is NumericHealthValue) {
              totalHR += value.numericValue;
              hrCount++;
            }
            break;
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            if (value is NumericHealthValue) {
              calories += value.numericValue;
            }
            break;
          case HealthDataType.SLEEP_ASLEEP:
            if (value is NumericHealthValue) {
              sleepMinutes += value.numericValue;
            }
            break;
          default:
            break;
        }
      }

      final avgHR = hrCount > 0 ? (totalHR / hrCount).round() : 0;
      final sleepHrs = (sleepMinutes / 60).round();
      final calInt = calories.round();

      if (steps == 0 && avgHR == 0 && calInt == 0 && sleepHrs == 0) {
        setState(() {
          _syncingAppleHealth = false;
          _lastSyncStatus = "No Apple Health data found in the last 24 hours. "
              "Make sure your Apple Watch is paired and syncing.";
        });
        return;
      }

      // POST to eHospital DB
      await EHospitalService.sendWearableVitals(
        heartRate: avgHR,
        steps: steps,
        calories: calInt,
        sleep: sleepHrs,
      );

      if (mounted) {
        setState(() {
          _syncingAppleHealth = false;
          _lastSyncStatus =
              "✓ Synced from Apple Watch  ·  "
              "Steps: $steps  ·  HR: ${avgHR} bpm  ·  "
              "Cal: $calInt  ·  Sleep: ${sleepHrs}h";
        });
        _loadData(); // refresh charts
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncingAppleHealth = false;
          _lastSyncStatus = "Sync error: $e";
        });
      }
    }
  }

  // ── Log Vitals to eHospital ──────────────────────────────────────────────
  void _showLogVitalsSheet() {
    final hrCtrl  = TextEditingController();
    final stCtrl  = TextEditingController();
    final calCtrl = TextEditingController();
    final slCtrl  = TextEditingController();
    bool sending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: const BoxDecoration(
                      color: AppColors.primarySoft, shape: BoxShape.circle),
                  child: const Icon(Icons.upload_outlined,
                      size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Log Vitals to eHospital",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                          color: AppColors.textDark)),
                  Text("POST → /table/wearable_vitals",
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _logField(hrCtrl,  "Heart Rate (bpm)", Icons.favorite_border, Colors.red)),
                const SizedBox(width: 10),
                Expanded(child: _logField(stCtrl,  "Steps", Icons.directions_walk, Colors.blue)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _logField(calCtrl, "Calories", Icons.local_fire_department_outlined, Colors.orange)),
                const SizedBox(width: 10),
                Expanded(child: _logField(slCtrl,  "Sleep (hrs)", Icons.bedtime_outlined, Colors.indigo)),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: sending
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(sending ? "Sending…" : "Send to eHospital"),
                  onPressed: sending
                      ? null
                      : () async {
                          final hr  = int.tryParse(hrCtrl.text.trim())  ?? 0;
                          final st  = int.tryParse(stCtrl.text.trim())  ?? 0;
                          final cal = int.tryParse(calCtrl.text.trim()) ?? 0;
                          final sl  = int.tryParse(slCtrl.text.trim())  ?? 0;
                          if (hr == 0 && st == 0 && cal == 0 && sl == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Enter at least one value")));
                            return;
                          }
                          setS(() => sending = true);
                          await EHospitalService.sendWearableVitals(
                            heartRate: hr, steps: st, calories: cal, sleep: sl);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    "✓ Vitals saved to eHospital DB"),
                                backgroundColor: Colors.green));
                            _loadData(); // refresh chart
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logField(TextEditingController ctrl, String label,
      IconData icon, Color color) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: color, size: 18),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  // ── Data Pipeline Card ──────────────────────────────────────────────────
  Widget _buildPipelineCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: const BoxDecoration(
                  color: AppColors.primarySoft, shape: BoxShape.circle),
              child: const Icon(Icons.share_outlined,
                  size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            const Text("Live Data Pipeline",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text("ACTIVE",
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
            ),
          ]),
          const SizedBox(height: 14),

          // Pipeline flow
          Row(children: [
            _pipelineStep(Icons.watch_outlined, "Apple Watch",
                "Sensor data", Colors.blue),
            _pipelineArrow(),
            _pipelineStep(Icons.favorite_outlined, "Apple Health",
                "iOS store", Colors.pink),
            _pipelineArrow(),
            _pipelineStep(Icons.cloud_upload_outlined, "eHospital DB",
                "$_wearableRecordCount records", AppColors.primary),
            _pipelineArrow(),
            _pipelineStep(Icons.analytics_outlined, "Analysis",
                "Insights screen", Colors.teal),
          ]),
        ],
      ),
    );
  }

  Widget _pipelineStep(
      IconData icon, String label, String sub, Color color) {
    return Expanded(
      child: Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark)),
        Text(sub,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
      ]),
    );
  }

  Widget _pipelineArrow() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Icon(Icons.arrow_forward_ios,
          size: 10, color: AppColors.textMuted),
    );
  }

  // ── Apple Health sync status banner ─────────────────────────────────────
  Widget _buildSyncBanner() {
    if (_syncingAppleHealth) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: const Row(children: [
          SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary)),
          SizedBox(width: 12),
          Text("Syncing from Apple Watch…",
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
        ]),
      );
    }
    if (_lastSyncStatus != null) {
      final isError = _lastSyncStatus!.startsWith("✓") == false;
      final color = isError ? Colors.orange : Colors.green;
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(isError ? Icons.warning_amber_outlined : Icons.check_circle_outline,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_lastSyncStatus!,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: () => setState(() => _lastSyncStatus = null),
            child: Icon(Icons.close, size: 16, color: color),
          ),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vital Signs"),
        actions: [
          // Device Manager
          IconButton(
            icon: const Icon(Icons.devices_outlined),
            tooltip: "Device Manager",
            onPressed: () => Navigator.pushNamed(context, "/devices"),
          ),
          // Apple Watch sync button
          _syncingAppleHealth
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
                )
              : IconButton(
                  icon: const Icon(Icons.watch_outlined),
                  tooltip: "Sync from Apple Watch",
                  onPressed: _syncFromAppleHealth,
                ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: "Log Vitals manually",
            onPressed: _showLogVitalsSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _syncFromAppleHealth,
        backgroundColor: AppColors.primary,
        icon: _syncingAppleHealth
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.watch_outlined, color: Colors.white),
        label: Text(
          _syncingAppleHealth ? "Syncing…" : "Sync Apple Watch",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSyncBanner(),
                  _buildClinicalCard(),
                  const SizedBox(height: 24),
                  _buildTabRow(),
                  const SizedBox(height: 12),
                  _buildRangeFilter(),
                  const SizedBox(height: 16),
                  _buildChartCard(),
                  const SizedBox(height: 16),
                  if (_hasZeroHR) _buildWarningBanner(),
                ],
              ),
            ),
    );
  }

  // ── Clinical Reference Card ──────────────────────────────────────────────
  Widget _buildClinicalCard() {
    Color ecgColor;
    switch (_clinicalECG.toLowerCase()) {
      case "abnormal": ecgColor = Colors.red; break;
      case "borderline": ecgColor = Colors.orange; break;
      default: ecgColor = Colors.green;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history_edu, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              "Clinical Reference",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text("eHospital", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
          ]),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _clinicalStat("ECG", _clinicalECG, Icons.show_chart, ecgColor),
              _divider(),
              _clinicalStat("Heart Rate", "${_liveBaselineHR.toInt()} BPM", Icons.favorite, Colors.redAccent),
              _divider(),
              _clinicalStat("Blood Pressure", _liveBaselineBP, Icons.water_drop_outlined, Colors.lightBlueAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _clinicalStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
      ],
    );
  }

  Widget _divider() => Container(width: 1, height: 50, color: Colors.white.withOpacity(0.2));

  // ── Time range filter ────────────────────────────────────────────────────
  Widget _buildRangeFilter() {
    const options = [
      (label: "7D",  days: 7),
      (label: "14D", days: 14),
      (label: "30D", days: 30),
      (label: "All", days: 0),
    ];
    return Row(
      children: options.map((o) {
        final selected = _rangeDays == o.days;
        return GestureDetector(
          onTap: () {
            if (_rangeDays == o.days) return;
            setState(() { _rangeDays = o.days; _aiSummaries.clear(); });
            _applyRange(triggerAI: true);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (selected ? AppColors.primary : Colors.black).withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              o.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Custom pill tab row ──────────────────────────────────────────────────
  Widget _buildTabRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final tab = _tabs[i];
          final selected = selectedIndex == i;
          return GestureDetector(
            onTap: () => setState(() => selectedIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? tab.color : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: (selected ? tab.color : Colors.black).withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tab.icon, size: 16, color: selected ? Colors.white : tab.color),
                  const SizedBox(width: 6),
                  Text(
                    tab.label,
                    style: TextStyle(
                      color: selected ? Colors.white : tab.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Chart card ───────────────────────────────────────────────────────────
  Widget _buildChartCard() {
    // ── Per-metric config ────────────────────────────────────────────────────
    const units        = ["steps",   "kcal",    "bpm",     "hrs"];
    const maxYs        = [20000.0,   800.0,     160.0,     12.0];
    const normalMins   = [5000.0,    300.0,     60.0,      7.0];
    const normalMaxs   = [15000.0,   600.0,     100.0,     9.0];
    const descriptions = [
      "Steps walked today. A healthy goal is 10,000 steps per day.",
      "Active calories burned. Healthy range: 300–600 kcal/day.",
      "Heart rate in beats per minute. Normal resting: 60–100 bpm.",
      "Hours of sleep recorded. Recommended: 7–9 hours per night.",
    ];
    const dataNotes = [
      "",
      "",
      "Green dashed line = clinical baseline HR from hospital records.",
      "0 hrs means the wearable did not record sleep for that period.",
    ];

    final tab        = _tabs[selectedIndex];
    final spots      = [stepSpots, calorieSpots, heartRateSpots, sleepSpots][selectedIndex];
    final unit       = units[selectedIndex];
    final normalMin  = normalMins[selectedIndex];
    final normalMax  = normalMaxs[selectedIndex];

    // Stats — exclude 0s so averages aren't skewed by missing data
    final nonZero = spots.map((s) => s.y).where((v) => v > 0).toList();
    final latest  = spots.isNotEmpty ? spots.last.y  : 0.0;
    final avg     = nonZero.isNotEmpty ? nonZero.reduce((a, b) => a + b) / nonZero.length : 0.0;
    final minVal  = nonZero.isNotEmpty ? nonZero.reduce((a, b) => a < b ? a : b) : 0.0;
    final maxVal  = nonZero.isNotEmpty ? nonZero.reduce((a, b) => a > b ? a : b) : 0.0;

    String fmt(double v) => v >= 1000
        ? "${(v / 1000).toStringAsFixed(1)}k"
        : v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

    // Status based on latest reading
    String statusLabel;
    Color  statusColor;
    if (latest <= 0) {
      statusLabel = "No Data";  statusColor = Colors.grey;
    } else if (latest < normalMin) {
      statusLabel = "Low";      statusColor = Colors.orange;
    } else if (latest > normalMax) {
      statusLabel = "High";     statusColor = Colors.red;
    } else {
      statusLabel = "Normal";   statusColor = Colors.green;
    }

    final latestLabel = timeLabels.isNotEmpty ? timeLabels.last : "";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ────────────────────────────────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: tab.color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(tab.icon, color: tab.color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("${tab.label} Trend",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 2),
                Text(descriptions[selectedIndex],
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ),
            const SizedBox(width: 8),
            // Latest value + status badge
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                latest > 0 ? "${fmt(latest)} $unit" : "— $unit",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: tab.color),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
              ),
              const SizedBox(height: 2),
              if (latestLabel.isNotEmpty)
                Text(latestLabel, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
            ]),
          ]),

          const SizedBox(height: 6),

          // ── Normal range legend ───────────────────────────────────────
          Row(children: [
            Container(width: 14, height: 3,
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 5),
            Text(
              "Normal range: ${fmt(normalMin)}–${fmt(normalMax)} $unit",
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ]),

          const SizedBox(height: 12),

          // ── Chart ─────────────────────────────────────────────────────
          SizedBox(
            height: 260,
            child: LineChart(LineChartData(
              maxY: maxYs[selectedIndex],
              minY: 0,
              rangeAnnotations: RangeAnnotations(
                horizontalRangeAnnotations: [
                  HorizontalRangeAnnotation(
                    y1: normalMin,
                    y2: normalMax,
                    color: Colors.green.withOpacity(0.07),
                  ),
                ],
              ),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: normalMin,
                  color: Colors.green.withOpacity(0.35),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
                HorizontalLine(
                  y: normalMax,
                  color: Colors.green.withOpacity(0.35),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ]),
              lineBarsData: [
                if (selectedIndex == 2)
                  LineChartBarData(
                    spots: [
                      FlSpot(0, _liveBaselineHR),
                      FlSpot(timeLabels.isEmpty ? 0 : (timeLabels.length - 1).toDouble(), _liveBaselineHR),
                    ],
                    color: Colors.green.withOpacity(0.5),
                    dashArray: [5, 5],
                    dotData: const FlDotData(show: false),
                    barWidth: 2,
                  ),
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: tab.color,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: tab.color.withOpacity(0.08)),
                ),
              ],
              titlesData: _buildTitlesData(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade100, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              clipData: const FlClipData.all(),
            )),
          ),

          // ── Stats row ─────────────────────────────────────────────────
          if (nonZero.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: tab.color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statCell("Latest",  latest > 0 ? "${fmt(latest)} $unit"  : "No data", tab.color),
                  _statDivider(),
                  _statCell("Average", "${fmt(avg)} $unit",    Colors.blueGrey),
                  _statDivider(),
                  _statCell("Min",     "${fmt(minVal)} $unit", Colors.green),
                  _statDivider(),
                  _statCell("Max",     "${fmt(maxVal)} $unit", Colors.orange),
                ],
              ),
            ),
          ],

          // ── Written summary ───────────────────────────────────────────
          const SizedBox(height: 14),
          _buildWrittenSummary(
            index: selectedIndex,
            statusLabel: statusLabel,
            statusColor: statusColor,
          ),

          // ── Data note ─────────────────────────────────────────────────
          if (dataNotes[selectedIndex].isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  dataNotes[selectedIndex],
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 28, color: Colors.grey.shade200);

  // ── AI-powered written summary ──────────────────────────────────────────
  Widget _buildWrittenSummary({
    required int index,
    required String statusLabel,
    required Color statusColor,
  }) {
    final aiText  = _aiSummaries[index];
    final loading = _aiGenerating && aiText == null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              statusLabel == "Normal"
                  ? Icons.check_circle_outline
                  : statusLabel == "No Data"
                      ? Icons.help_outline
                      : Icons.warning_amber_outlined,
              color: statusColor,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text("AI Health Insight",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text("Gemini AI",
                  style: TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          if (loading)
            const Row(children: [
              SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
              SizedBox(width: 8),
              Text("Generating insight…",
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ])
          else if (aiText != null && aiText.isNotEmpty)
            Text(aiText,
                style: const TextStyle(fontSize: 12, color: AppColors.textDark, height: 1.5))
          else
            const Text("Sync data to generate an AI insight.",
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  FlTitlesData _buildTitlesData() {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i >= 0 && i < timeLabels.length && i % 10 == 0 && i < timeLabels.length - 5) {
              return Transform.rotate(
                angle: -0.5,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    timeLabels[i],
                    style: const TextStyle(fontSize: 7, color: Colors.black38),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
          reservedSize: 44,
        ),
      ),
      leftTitles: AxisTitles(sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 38,
        getTitlesWidget: (v, _) => Text(v.toInt().toString(),
            style: const TextStyle(fontSize: 10, color: Colors.black38)),
      )),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      // Reserve 16px on the right so the last dot doesn't clip
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false, reservedSize: 16)),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.red.shade100, shape: BoxShape.circle),
          child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            "Data sync issue: Heart rate recorded as 0 BPM. Wearable may not be syncing correctly.",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ]),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;
  final Color color;
  const _TabItem({required this.icon, required this.label, required this.color});
}
