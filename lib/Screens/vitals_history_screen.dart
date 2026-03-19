import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../ui/app_theme.dart';

class VitalsHistoryScreen extends StatefulWidget {
  const VitalsHistoryScreen({Key? key}) : super(key: key);

  @override
  State<VitalsHistoryScreen> createState() => _VitalsHistoryScreenState();
}

class _VitalsHistoryScreenState extends State<VitalsHistoryScreen> {
  bool loading = true;
  List<dynamic> vitals = [];

  // Chart data (oldest → newest for left-to-right trend)
  List<FlSpot> heartRateSpots = [];
  List<FlSpot> temperatureSpots = [];
  List<FlSpot> respiratorySpots = [];
  List<FlSpot> systolicSpots = [];
  List<FlSpot> diastolicSpots = [];
  List<String> timeLabels = [];
  List<int> _bottomTitleIndices = [];
  int selectedIndex = 0;

  List<dynamic> labTests = [];
  List<dynamic> diabetes = [];
  List<dynamic> heartDisease = [];
  List<dynamic> ecgList = [];
  List<dynamic> strokeData = [];
  List<dynamic> diagnosisList = [];

  static const String _baseUrl = "https://aetab8pjmb.us-east-1.awsapprunner.com/table";

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getInt("patient_id");

    if (patientId == null) return;

    debugPrint("[VitalsHistory] Loading history for patient_id=$patientId");

    final url = Uri.parse(
      "https://aetab8pjmb.us-east-1.awsapprunner.com/table/vitals_history?patient_id=$patientId",
    );

    final res = await http.get(url);

    if (res.statusCode == 200) {
      final jsonBody = jsonDecode(res.body);
      final rawList = jsonBody["data"] as List<dynamic>? ?? [];

      final filtered = rawList.where((item) {
        final id = item["patient_id"];
        if (id == null) return true;
        final match = id is int ? id == patientId : id.toString() == patientId.toString();
        return match;
      }).toList();

      final tsKey = (dynamic item) => item["timestamp"] ?? item["recorded_on"] ?? "";
      filtered.sort((a, b) => DateTime.parse(tsKey(a)).compareTo(DateTime.parse(tsKey(b))));

      _buildChartData(filtered);

      final results = await Future.wait([
        _fetchTableForPatient("lab_tests", patientId),
        _fetchTableForPatient("diabetes_analysis", patientId),
        _fetchTableForPatient("heart_disease_analysis", patientId),
        _fetchTableForPatient("ecg", patientId),
        _fetchTableForPatient("stroke_prediction", patientId),
        _fetchTableForPatient("diagnosis", patientId),
      ]);

      if (mounted) {
        setState(() {
          vitals = filtered;
          labTests = results[0];
          diabetes = results[1];
          heartDisease = results[2];
          ecgList = results[3];
          strokeData = results[4];
          diagnosisList = results[5];
          loading = false;
        });
      }
    } else {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<dynamic>> _fetchTableForPatient(String table, int patientId) async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/$table?patient_id=$patientId"));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body);
      final raw = body["data"] as List<dynamic>? ?? [];
      return raw.where((e) {
        final id = e["patient_id"];
        if (id == null) return true;
        return id is int ? id == patientId : id.toString() == patientId.toString();
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void _buildChartData(List<dynamic> sortedVitals) {
    heartRateSpots = [];
    temperatureSpots = [];
    respiratorySpots = [];
    systolicSpots = [];
    diastolicSpots = [];
    timeLabels = [];

    for (int i = 0; i < sortedVitals.length; i++) {
      final v = sortedVitals[i];
      final ts = v["timestamp"] ?? v["recorded_on"] ?? "";
      timeLabels.add(_formatAxisDate(ts.toString()));

      final hr = _toDouble(v["heart_rate"]);
      final temp = _toDouble(v["temperature"]);
      final resp = _toDouble(v["respiratory_rate"]);
      final bp = _parseBloodPressure(v["blood_pressure"]);

      heartRateSpots.add(FlSpot(i.toDouble(), hr));
      temperatureSpots.add(FlSpot(i.toDouble(), temp));
      respiratorySpots.add(FlSpot(i.toDouble(), resp));
      systolicSpots.add(FlSpot(i.toDouble(), bp.$1));
      diastolicSpots.add(FlSpot(i.toDouble(), bp.$2));
    }
    _buildBottomTitleIndices();
  }

  void _buildBottomTitleIndices() {
    final n = timeLabels.length;
    if (n == 0) {
      _bottomTitleIndices = [];
      return;
    }
    final step = n <= 5 ? 1 : (n / 5).ceil();
    final candidates = <int>{0};
    for (int i = step; i < n - 1; i += step) candidates.add(i);
    if (n > 1) candidates.add(n - 1);
    final seen = <String>{};
    _bottomTitleIndices = [];
    for (final i in candidates.toList()..sort()) {
      final t = timeLabels[i];
      if (seen.contains(t)) continue;
      seen.add(t);
      _bottomTitleIndices.add(i);
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  (double, double) _parseBloodPressure(dynamic value) {
    if (value == null) return (0.0, 0.0);
    final s = value.toString().trim().split("/");
    if (s.length < 2) return (0.0, 0.0);
    final sys = double.tryParse(s[0].trim()) ?? 0.0;
    final dia = double.tryParse(s[1].trim()) ?? 0.0;
    return (sys, dia);
  }

  String _formatAxisDate(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return DateFormat("MM/dd HH:mm").format(dt);
    } catch (_) {
      return "";
    }
  }

  String _valueLabelAt(int i) {
    if (i < 0) return "";
    if (selectedIndex == 0 && i < heartRateSpots.length) {
      return "${heartRateSpots[i].y.toInt()} bpm";
    }
    if (selectedIndex == 1 && i < temperatureSpots.length) {
      return "${temperatureSpots[i].y.toStringAsFixed(1)} °C";
    }
    if (selectedIndex == 2 && i < respiratorySpots.length) {
      return "${respiratorySpots[i].y.toInt()} /min";
    }
    if (selectedIndex == 3 && i < systolicSpots.length) {
      return "${systolicSpots[i].y.toInt()}/${diastolicSpots[i].y.toInt()}";
    }
    return "";
  }

  static const _historyTabs = [
    _HistoryTab(icon: Icons.favorite_border, label: "Heart Rate", color: Colors.red),
    _HistoryTab(icon: Icons.thermostat, label: "Temperature", color: Colors.orange),
    _HistoryTab(icon: Icons.air, label: "Respiratory", color: Colors.teal),
    _HistoryTab(icon: Icons.monitor_heart, label: "Blood Pressure", color: Colors.blue),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Vitals History")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Gradient summary banner ─────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
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
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.history, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text("Clinical Vitals History",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text("${vitals.length} record${vitals.length == 1 ? '' : 's'} found",
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 24),

                  if (vitals.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.07), blurRadius: 10)],
                      ),
                      child: const Center(
                        child: Text("No vitals history found",
                            style: TextStyle(fontSize: 15, color: AppColors.textMuted)),
                      ),
                    )
                  else ...[
                    // ── Custom pill tabs ──────────────────────────────
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_historyTabs.length, (i) {
                          final tab = _historyTabs[i];
                          final sel = selectedIndex == i;
                          return GestureDetector(
                            onTap: () => setState(() => selectedIndex = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: sel ? tab.color : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [BoxShadow(
                                  color: (sel ? tab.color : Colors.black).withOpacity(0.1),
                                  blurRadius: 8, offset: const Offset(0, 3),
                                )],
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(tab.icon, size: 15, color: sel ? Colors.white : tab.color),
                                const SizedBox(width: 6),
                                Text(tab.label,
                                    style: TextStyle(
                                        color: sel ? Colors.white : tab.color,
                                        fontWeight: FontWeight.w600, fontSize: 13)),
                              ]),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildChartSection(),
                  ],

                  const SizedBox(height: 28),

                  // ── Related Records header ────────────────────────
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                      child: const Icon(Icons.folder_open_outlined, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text("Related Records",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  ]),
                  const SizedBox(height: 14),
                  _buildDataCard("Lab Tests", labTests, Icons.biotech, _buildLabTestTile),
                  _buildDataCard("ECG", ecgList, Icons.monitor_heart, _buildEcgTile),
                  _buildDataCard("Diabetes Analysis", diabetes, Icons.bloodtype, _buildDiabetesTile),
                  _buildDataCard("Heart Disease Analysis", heartDisease, Icons.favorite, _buildHeartDiseaseTile),
                  _buildDataCard("Stroke Prediction", strokeData, Icons.warning_amber_outlined, _buildStrokePredictionTile),
                  _buildDataCard("Diagnosis", diagnosisList, Icons.medical_services_outlined, _buildDiagnosisTile),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildDataCard(String title, List<dynamic> items, IconData icon, Widget Function(dynamic) tileBuilder) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              const Spacer(),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text("${items.length}",
                      style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
            ]),
            if (items.isEmpty) ...[
              const SizedBox(height: 12),
              const Text("No data available", style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ] else ...[
              const SizedBox(height: 14),
              ...items.take(5).map((e) => tileBuilder(e)),
              if (items.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text("+ ${items.length - 5} more records",
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabTestTile(dynamic e) {
    final type = e["test_type"]?.toString() ?? "—";
    final status = e["status"]?.toString() ?? "—";
    final result = e["result"]?.toString() ?? "—";
    final location = e["lab_location"]?.toString() ?? "—";
    final sampleType = e["sample_type"]?.toString() ?? "—";
    final raw = e["test_date"]?.toString() ?? "";
    String dateStr = raw;
    try { dateStr = DateFormat("MMM dd, yyyy").format(DateTime.parse(raw)); } catch (_) {}

    // Color-code result
    Color resultColor = Colors.green;
    if (result.toLowerCase() == "abnormal" || result.toLowerCase() == "positive") {
      resultColor = Colors.red;
    } else if (result.toLowerCase() == "pending" || status.toLowerCase() == "processing") {
      resultColor = Colors.orange;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(result,
                    style: TextStyle(fontSize: 12, color: resultColor, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),
            Text("Status: $status  ·  Sample: $sampleType",
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Text("Location: $location  ·  $dateStr",
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildEcgTile(dynamic e) {
    final result = e["ecg_result"]?.toString() ?? "—";
    final on = e["recorded_on"]?.toString() ?? "—";
    String dateStr = on;
    try {
      dateStr = DateFormat("MMM dd, yyyy").format(DateTime.parse(on));
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Result: $result", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiabetesTile(dynamic e) {
    final glucose = e["glucose_level"]?.toString() ?? "—";
    final insulin = e["insulin"]?.toString() ?? "—";
    final prediction = e["prediction"]?.toString() ?? "—";
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Prediction: $prediction", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text("Glucose: $glucose · Insulin: $insulin", style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildHeartDiseaseTile(dynamic e) {
    final prediction = e["prediction"]?.toString() ?? "—";
    final risk = e["risk_score"]?.toString() ?? "—";
    final cholesterol = e["cholesterol"]?.toString() ?? "—";
    final bp = e["resting_bp"]?.toString() ?? "—";
    final date = e["analyzed_on"]?.toString() ?? "—";
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Prediction: $prediction · Risk: $risk", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text("Cholesterol: $cholesterol · BP: $bp · $date", style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildStrokePredictionTile(dynamic e) {
    final riskScore = _toDouble(e["risk_score"]);
    final modelVersion = e["model_version"]?.toString() ?? "—";
    final raw = e["predicted_on"]?.toString() ?? "";
    String dateStr = raw;
    try { dateStr = DateFormat("MMM dd, yyyy").format(DateTime.parse(raw)); } catch (_) {}

    // Classify risk level from score
    String riskLabel;
    Color riskColor;
    if (riskScore >= 0.7) { riskLabel = "High Risk"; riskColor = Colors.red; }
    else if (riskScore >= 0.4) { riskLabel = "Moderate Risk"; riskColor = Colors.orange; }
    else { riskLabel = "Low Risk"; riskColor = Colors.green; }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text("Risk Score: ${(riskScore * 100).toStringAsFixed(0)}%",
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: riskColor.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                    child: Text(riskLabel, style: TextStyle(fontSize: 11, color: riskColor, fontWeight: FontWeight.bold)),
                  ),
                ]),
                Text("Model: $modelVersion · $dateStr",
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisTile(dynamic e) {
    final code = e["diagnosis_code"]?.toString() ?? "—";
    final description = e["diagnosis_description"]?.toString() ?? "—";
    final raw = e["diagnosis_date"]?.toString() ?? "";
    String dateStr = raw;
    try { dateStr = DateFormat("MMM dd, yyyy").format(DateTime.parse(raw)); } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(4)),
                    child: Text(code, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    final titles = ["Heart Rate", "Temperature", "Respiratory Rate", "Blood Pressure"];
    final title = titles[selectedIndex];
    double maxY;
    List<LineChartBarData> lineBars;
    if (selectedIndex == 0) {
      maxY = (heartRateSpots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b) + 20).clamp(60.0, 200.0);
      lineBars = [
        LineChartBarData(
          spots: heartRateSpots,
          isCurved: true,
          color: Colors.red,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: Colors.red.withOpacity(0.1)),
        ),
      ];
    } else if (selectedIndex == 1) {
      maxY = (temperatureSpots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b) + 1).clamp(35.0, 42.0);
      lineBars = [
        LineChartBarData(
          spots: temperatureSpots,
          isCurved: true,
          color: Colors.orange,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: Colors.orange.withOpacity(0.1)),
        ),
      ];
    } else if (selectedIndex == 2) {
      maxY = (respiratorySpots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b) + 5).clamp(10.0, 40.0);
      lineBars = [
        LineChartBarData(
          spots: respiratorySpots,
          isCurved: true,
          color: Colors.teal,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.1)),
        ),
      ];
    } else {
      final allSys = systolicSpots.map((s) => s.y);
      final allDia = diastolicSpots.map((s) => s.y);
      final maxVal = [...allSys, ...allDia].fold(0.0, (a, b) => a > b ? a : b);
      maxY = (maxVal + 20).clamp(80.0, 200.0);
      lineBars = [
        LineChartBarData(
          spots: systolicSpots,
          isCurved: true,
          color: Colors.blue,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
        LineChartBarData(
          spots: diastolicSpots,
          isCurved: true,
          color: Colors.purple,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$title — Trend", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (selectedIndex == 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: Colors.blue),
                const SizedBox(width: 6),
                const Text("Systolic", style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(width: 16),
                Icon(Icons.circle, size: 10, color: Colors.purple),
                const SizedBox(width: 6),
                const Text("Diastolic", style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: LineChart(
            LineChartData(
              maxY: maxY,
              minY: selectedIndex == 1 ? 35.0 : 0,
              lineBarsData: lineBars,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= timeLabels.length || !_bottomTitleIndices.contains(i)) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          timeLabels[i],
                          style: const TextStyle(fontSize: 9, color: Colors.black54),
                        ),
                      );
                    },
                    reservedSize: 24,
                  ),
                ),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryTab {
  final IconData icon;
  final String label;
  final Color color;
  const _HistoryTab({required this.icon, required this.label, required this.color});
}
