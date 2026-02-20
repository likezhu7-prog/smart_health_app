import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class VitalsHistoryScreen extends StatefulWidget {
  const VitalsHistoryScreen({Key? key}) : super(key: key);

  @override
  State<VitalsHistoryScreen> createState() => _VitalsHistoryScreenState();
}

class _VitalsHistoryScreenState extends State<VitalsHistoryScreen> {
  bool loading = true;
  List<dynamic> vitals = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getInt("patient_id");

    if (patientId == null) return;

    final url = Uri.parse(
      "https://aetab8pjmb.us-east-1.awsapprunner.com/table/wearable_vitals?patient_id=$patientId",
    );

    final res = await http.get(url);

    if (res.statusCode == 200) {
      final jsonBody = jsonDecode(res.body);

      // Sort newest → oldest
      List<dynamic> sorted = jsonBody["data"];
      sorted.sort((a, b) =>
          DateTime.parse(b["timestamp"])
              .compareTo(DateTime.parse(a["timestamp"])));

      setState(() {
        vitals = sorted;
        loading = false;
      });
    } else {
      setState(() => loading = false);
    }
  }

  String formatDate(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return DateFormat("MMM dd, yyyy — hh:mm a").format(dt);
    } catch (e) {
      return timestamp;
    }
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
          : vitals.isEmpty
              ? const Center(
                  child: Text(
                    "No vitals found",
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: vitals.length,
                  itemBuilder: (context, i) {
                    final v = vitals[i];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title row
                            Row(
                              children: const [
                                Icon(Icons.monitor_heart,
                                    color: Color(0xFF6A1B9A)),
                                SizedBox(width: 8),
                                Text(
                                  "Vitals Record",
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            Text(
                              formatDate(v["timestamp"]),
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.grey),
                            ),

                            const Divider(height: 22),

                            _info("Heart Rate", "${v["heart_rate"]} bpm"),
                            _info("Steps", "${v["steps"]}"),
                            _info("Calories", "${v["calories"]} kcal"),
                            _info("Sleep", "${v["sleep"]} mins"),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 15, color: Colors.black54)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
