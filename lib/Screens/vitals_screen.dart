import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/e_hospital_service.dart';

class VitalsScreen extends StatefulWidget {
  const VitalsScreen({super.key});

  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  List<FlSpot> stepSpots = [];
  List<FlSpot> calorieSpots = [];
  List<FlSpot> heartRateSpots = [];
  List<String> timeLabels = []; 
  bool isLoading = true;
  int selectedIndex = 0; 
  String currentPatientId = "20";
  String? _ecgResult; // from API https://aetab8pjmb.us-east-1.awsapprunner.com/table/ecg

  // Baseline HR & BP per patient_id (ECG comes from API above)
  static const Map<String, Map<String, dynamic>> _clinicalByPatient = {
    "1": {"hr": 68.0, "bp": "118/76"},
    "2": {"hr": 74.0, "bp": "122/78"},
    "3": {"hr": 70.0, "bp": "119/77"},
    "4": {"hr": 78.0, "bp": "128/82"},
    "5": {"hr": 66.0, "bp": "115/75"},
    "6": {"hr": 72.0, "bp": "120/80"},
    "7": {"hr": 71.0, "bp": "121/79"},
    "8": {"hr": 75.0, "bp": "124/80"},
    "9": {"hr": 69.0, "bp": "117/76"},
    "10": {"hr": 67.0, "bp": "116/74"},
    "20": {"hr": 72.0, "bp": "120/80"},
  };

  double get _clinicalHR =>
      (_clinicalByPatient[currentPatientId]?["hr"] as num?)?.toDouble() ?? 72.0;
  String get _clinicalBP =>
      _clinicalByPatient[currentPatientId]?["bp"] as String? ?? "120/80";
  String get _clinicalECG => _ecgResult ?? "Unknown";

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

    // Fetch ECG for current patient from API
    String? ecgResult;
    try {
      final ecgRes = await http.get(Uri.parse(
          "https://aetab8pjmb.us-east-1.awsapprunner.com/table/ecg"));
      if (ecgRes.statusCode == 200) {
        final ecgBody = jsonDecode(ecgRes.body);
        final ecgList = ecgBody["data"] as List<dynamic>? ?? [];
        final forPatient = ecgList
            .where((e) => e["patient_id"].toString() == searchId)
            .toList();
        if (forPatient.isNotEmpty) {
          forPatient.sort((a, b) =>
              (b["recorded_on"] ?? "").compareTo(a["recorded_on"] ?? ""));
          ecgResult = forPatient.first["ecg_result"]?.toString();
        }
      }
    } catch (_) {}

    final List<dynamic> rawData = await EHospitalService.fetchVitals();
    final filteredData = rawData
        .where((item) => item['patient_id'].toString() == searchId)
        .toList();
    filteredData.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));

    List<FlSpot> sSpots = [];
    List<FlSpot> cSpots = [];
    List<FlSpot> hrSpots = [];
    List<String> labels = [];

    for (int i = 0; i < filteredData.length; i++) {
      double s = double.tryParse(filteredData[i]['steps'].toString()) ?? 0.0;
      double c = double.tryParse(filteredData[i]['calories'].toString()) ?? 0.0;
      double hr = double.tryParse(filteredData[i]['heart_rate'].toString()) ?? 0.0;
      sSpots.add(FlSpot(i.toDouble(), s));
      cSpots.add(FlSpot(i.toDouble(), c));
      hrSpots.add(FlSpot(i.toDouble(), hr));
      DateTime time = DateTime.parse(filteredData[i]['timestamp']).toLocal();
      labels.add(DateFormat('MM/dd HH:mm').format(time));
    }

    if (mounted) {
      setState(() {
        currentPatientId = searchId;
        _ecgResult = ecgResult;
        stepSpots = sSpots;
        calorieSpots = cSpots;
        heartRateSpots = hrSpots;
        timeLabels = labels;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vital Signs Dashboard"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('patient_id');
              if (mounted) Navigator.pushReplacementNamed(context, "/");
            },
          )
        ],
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildClinicalContextCard(),
                const SizedBox(height: 24),
                Center(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Step Count'), icon: Icon(Icons.directions_walk)),
                      ButtonSegment(value: 1, label: Text('Calorie Expenditure'), icon: Icon(Icons.local_fire_department)),
                      ButtonSegment(value: 2, label: Text('Heart Rate'), icon: Icon(Icons.favorite_border)),
                    ],
                    selected: {selectedIndex},
                    onSelectionChanged: (val) => setState(() => selectedIndex = val.first),
                  ),
                ),
                const SizedBox(height: 20),
                _buildChartSection(),
                const SizedBox(height: 24),
                // 💡 只有 Patient 20 显示警告横幅
                if (currentPatientId == "20") _buildWarningBanner(),
              ],
            ),
          ),
    );
  }

  // --- 下面这些 UI 组件保持你原来的逻辑，不需要大改 ---

  Widget _buildClinicalContextCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_edu, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text("Clinical Reference (eHospital)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _clinicalInfo("ECG Result", _clinicalECG, Colors.orange),
                _clinicalInfo("Baseline Heart Rate", "${_clinicalHR.toInt()} BPM", Colors.green),
                _clinicalInfo("Blood Pressure", _clinicalBP, Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _clinicalInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildChartSection() {
    String title = ["Step Count", "Calorie Expenditure", "Heart Rate"][selectedIndex];
    double maxY = [5000.0, 100.0, 120.0][selectedIndex];
    Color themeColor = [Colors.blue, Colors.orange, Colors.red][selectedIndex];

    return Column(
      children: [
        Text("$title — Trend", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SizedBox(
          height: 300,
          child: LineChart(
            LineChartData(
              maxY: maxY,
              lineBarsData: [
                if (selectedIndex == 2)
                  LineChartBarData(
                    spots: [FlSpot(0, _clinicalHR), FlSpot(timeLabels.isEmpty ? 0 : (timeLabels.length - 1).toDouble(), _clinicalHR)],
                    color: Colors.green.withOpacity(0.4),
                    dashArray: [5, 5],
                    dotData: const FlDotData(show: false),
                  ),
                LineChartBarData(
                  spots: [stepSpots, calorieSpots, heartRateSpots][selectedIndex],
                  isCurved: true,
                  color: themeColor,
                  barWidth: 4,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: themeColor.withOpacity(0.1)),
                ),
              ],
              titlesData: _buildTitlesData(),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
            ),
          ),
        ),
      ],
    );
  }

  FlTitlesData _buildTitlesData() {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) {
            int index = value.toInt();
            if (index >= 0 && index < timeLabels.length && index % 10 == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(timeLabels[index], style: const TextStyle(fontSize: 8, color: Colors.black54)),
              );
            }
            return const SizedBox.shrink();
          },
          reservedSize: 40,
        ),
      ),
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: Colors.red.shade200)
      ),
      child: Row(
        children: const [
          Icon(Icons.report_problem, color: Colors.red),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Data synchronization discrepancy: Wearable heart rate is recorded as 0 BPM despite the presence of other active records.",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}