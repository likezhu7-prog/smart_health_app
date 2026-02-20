import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class EHospitalAuthService {
  static const String _baseUrl =
      "https://aetab8pjmb.us-east-1.awsapprunner.com";

  /// Login only by email.
  /// Looks up the user in /table/users and saves user_id as patient_id.
  static Future<bool> loginWithEmail(String email) async {
    try {
      final url = Uri.parse("$_baseUrl/table/users");
      final res = await http.get(url);

      if (res.statusCode != 200) {
        print(" Login API error: ${res.statusCode} ${res.body}");
        return false;
      }

      final body = jsonDecode(res.body);
      final List data = body["data"] ?? [];

      Map<String, dynamic>? user;

      for (final u in data) {
        final uEmail = (u["email"] ?? "").toString().toLowerCase();
        if (uEmail == email.toLowerCase()) {
          user = Map<String, dynamic>.from(u);
          break;
        }
      }

      if (user == null) {
        print(" No user found for email $email");
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt("patient_id", user["user_id"] as int);
      await prefs.setString("patient_email", user["email"] as String);
      await prefs.setString("patient_username", user["username"] as String);

      print(" Logged in as ${user["username"]} (patient_id=${user["user_id"]})");
      return true;
    } catch (e) {
      print(" loginWithEmail error: $e");
      return false;
    }
  }

  /// Helper: get currently logged-in patient_id
  static Future<int?> getLoggedInPatientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt("patient_id");
  }
}
