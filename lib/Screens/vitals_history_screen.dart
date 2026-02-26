import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

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

      final lab = await _fetchTableForPatient("lab_tests", patientId);
      final diab = await _fetchTableForPatient("diabetes_analysis", patientId);
      final heart = await _fetchTableForPatient("heart_disease_analysis", patientId);
      final ecg = await _fetchTableForPatient("ecg", patientId);

      if (mounted) {
        setState(() {
          vitals = filtered;
          labTests = lab;
          diabetes = diab;
          heartDisease = heart;
          ecgList = ecg;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        title: const Text("Vitals History"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vitals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Center(
                        child: Text("No vitals found", style: TextStyle(fontSize: 16, color: Colors.black54)),
                      ),
                    )
                  else ...[
                    Center(
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text("Heart Rate"), icon: Icon(Icons.favorite_border, size: 18)),
                          ButtonSegment(value: 1, label: Text("Temperature"), icon: Icon(Icons.thermostat, size: 18)),
                          ButtonSegment(value: 2, label: Text("Respiratory"), icon: Icon(Icons.air, size: 18)),
                          ButtonSegment(value: 3, label: Text("Blood Pressure"), icon: Icon(Icons.monitor_heart, size: 18)),
                        ],
                        selected: {selectedIndex},
                        onSelectionChanged: (v) => setState(() => selectedIndex = v.first),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildChartSection(),
                  ],
                  const SizedBox(height: 24),
                  const Text("Related Records", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildDataCard("Lab Tests", labTests, Icons.biotech, _buildLabTestTile),
                  _buildDataCard("ECG", ecgList, Icons.monitor_heart, _buildEcgTile),
                  _buildDataCard("Diabetes Analysis", diabetes, Icons.bloodtype, _buildDiabetesTile),
                  _buildDataCard("Heart Disease Analysis", heartDisease, Icons.favorite, _buildHeartDiseaseTile),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildDataCard(String title, List<dynamic> items, IconData icon, Widget Function(dynamic) tileBuilder) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.indigo, size: 22),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text("No data", style: TextStyle(fontSize: 14, color: Colors.black54))
            else
              ...items.take(5).map((e) => tileBuilder(e)),
            if (items.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text("+ ${items.length - 5} more", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabTestTile(dynamic e) {
    final type = e["test_type"]?.toString() ?? "—";
    final status = e["status"]?.toString() ?? "—";
    final result = e["result"]?.toString() ?? "—";
    final date = e["test_date"]?.toString() ?? "—";
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
                Text("$type · $status", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text("Result: $result · $date", style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
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
