import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:health/health.dart';
import '../services/e_hospital_service.dart';
import '../services/ai_health_service.dart';
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
  String currentPatientId = "20";
  String? _ecgResult;
  double _liveBaselineHR = 72.0;
  String _liveBaselineBP = "120/80";
  bool _hasZeroHR = false;

  // AI Health Agent state
  String? _aiAnalysis;
  bool _aiLoading = false;

  // Apple Health sync state
  bool _syncingAppleHealth = false;
  String? _lastSyncStatus;
  int _wearableRecordCount = 0; // total records in DB for this patient

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
    final int? loggedId = prefs.getInt("patient_id");
    final String searchId = (loggedId ?? 20).toString();

    String? ecgResult;
    try {
      final ecgRes = await http.get(Uri.parse(
          "https://aetab8pjmb.us-east-1.awsapprunner.com/table/ecg"));
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
          "https://aetab8pjmb.us-east-1.awsapprunner.com/table/vitals_history?patient_id=$searchId"));
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

    List<FlSpot> sSpots = [], cSpots = [], hrSpots = [], slSpots = [];
    List<String> labels = [];
    bool hasZero = false;

    for (int i = 0; i < filteredData.length; i++) {
      final d = filteredData[i];
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
        currentPatientId = searchId;
        _ecgResult = ecgResult;
        _liveBaselineHR = liveHR;
        _liveBaselineBP = liveBP;
        _hasZeroHR = hasZero;
        stepSpots = sSpots;
        calorieSpots = cSpots;
        heartRateSpots = hrSpots;
        sleepSpots = slSpots;
        timeLabels = labels;
        _wearableRecordCount = filteredData.length;
        isLoading = false;
      });
    }
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

  // ── AI Health Agent ──────────────────────────────────────────────────────
  Future<void> _analyzeWithAI() async {
    setState(() { _aiLoading = true; _aiAnalysis = null; });

    // Get latest vitals from chart data
    final latestHR = heartRateSpots.isNotEmpty
        ? heartRateSpots.last.y.toInt()
        : _liveBaselineHR.toInt();
    final latestSteps = stepSpots.isNotEmpty
        ? stepSpots.last.y.toInt()
        : 0;
    final latestCal = calorieSpots.isNotEmpty
        ? calorieSpots.last.y.toInt()
        : 0;
    final latestSleep = sleepSpots.isNotEmpty
        ? sleepSpots.last.y.toInt()
        : 0;

    final result = await AIHealthService.analyzeVitals(
      heartRate: latestHR,
      steps: latestSteps,
      calories: latestCal,
      sleep: latestSleep,
      ecgResult: _clinicalECG,
      bloodPressure: _liveBaselineBP,
    );

    if (mounted) {
      setState(() {
        _aiAnalysis = result;
        _aiLoading = false;
      });
    }
  }

  // ── AI Analysis Card ─────────────────────────────────────────────────────
  Widget _buildAICard() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.psychology_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Health Agent',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text('Powered by GPT Analysis',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 11)),
              ],
            ),
            const Spacer(),
            GestureDetector(
              onTap: _aiLoading ? null : _analyzeWithAI,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3)),
                ),
                child: _aiLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              size: 14, color: Colors.white),
                          SizedBox(width: 5),
                          Text('Analyze',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Content
          if (_aiAnalysis == null && !_aiLoading)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(children: [
                Icon(Icons.touch_app_outlined,
                    color: Colors.white60, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tap "Analyze" to get AI-powered health insights based on your latest vitals.',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13),
                  ),
                ),
              ]),
            )
          else if (_aiLoading)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white60),
                ),
                SizedBox(width: 12),
                Text('Analyzing your health data...',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ]),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _aiAnalysis!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.6),
              ),
            ),
        ],
      ),
    );
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
                  _buildPipelineCard(),
                  _buildSyncBanner(),
                  _buildClinicalCard(),
                  const SizedBox(height: 24),
                  _buildTabRow(),
                  const SizedBox(height: 16),
                  _buildChartCard(),
                  const SizedBox(height: 16),
                  if (_hasZeroHR) _buildWarningBanner(),
                  _buildAICard(),
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
    const maxYs = [5000.0, 400.0, 120.0, 12.0];
    const units = ["steps", "kcal", "bpm", "hrs"];
    final tab = _tabs[selectedIndex];
    final spots = [stepSpots, calorieSpots, heartRateSpots, sleepSpots][selectedIndex];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: tab.color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(tab.icon, color: tab.color, size: 18),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${tab.label} Trend",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              Text(units[selectedIndex],
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 260,
            child: LineChart(LineChartData(
              maxY: maxYs[selectedIndex],
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
            )),
          ),
          if (selectedIndex == 2) ...[
            const SizedBox(height: 8),
            Row(children: [
              Container(width: 18, height: 2, color: Colors.green.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text("Baseline HR (${_liveBaselineHR.toInt()} bpm · vitals_history)",
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ],
          if (selectedIndex == 3) ...[
            const SizedBox(height: 8),
            const Text("0 hrs = not recorded by wearable device",
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
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
            if (i >= 0 && i < timeLabels.length && i % 10 == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(timeLabels[i], style: const TextStyle(fontSize: 8, color: Colors.black38)),
              );
            }
            return const SizedBox.shrink();
          },
          reservedSize: 36,
        ),
      ),
      leftTitles: AxisTitles(sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 38,
        getTitlesWidget: (v, _) => Text(v.toInt().toString(),
            style: const TextStyle(fontSize: 10, color: Colors.black38)),
      )),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
