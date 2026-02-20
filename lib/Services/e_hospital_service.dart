import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class EHospitalService {
  static const String baseUrl =
      "https://aetab8pjmb.us-east-1.awsapprunner.com";

  /// Safe getter for current Patient ID
  static Future<String?> getCurrentPatientId() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Use get(key) to avoid getString crashing when value is int
    final Object? rawId = prefs.get('patient_id');
    
    if (rawId == null) return null;
    
    // Return as String whether stored as 20 or "20"
    return rawId.toString();
  }

  static Future<void> sendWearableVitals({
    String? patientId, 
    required int heartRate,
    required int steps,
    required int calories,
    required int sleep,
  }) async {
    // Ensure id is always a String
    final id = patientId ?? await getCurrentPatientId() ?? "unknown_user";
    
    final url = Uri.parse('$baseUrl/table/wearable_vitals');

    final data = {
      "patient_id": id, 
      "heart_rate": heartRate,
      "steps": steps,
      "calories": calories,
      "sleep": sleep,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      print("Wearable vitals saved for Patient: $id");
    } else {
      print("Failed to save → ${response.statusCode}");
      print(response.body);
    }
  }

  static Future<List<dynamic>> fetchVitals() async {
    final url = Uri.parse('$baseUrl/table/wearable_vitals');

    try {
      final response = await http.get(
        url,
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedData = jsonDecode(response.body);
        // Return a List; empty list if field missing
        return decodedData['data'] is List ? decodedData['data'] : [];
      } else {
        print("Failed to fetch data → ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("Network error in fetchVitals: $e");
      return [];
    }
  }
}