import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../ui/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  Map<String, dynamic>? _user;
  String? _errorMsg;

  static const String _baseUrl =
      "https://aetab8pjmb.us-east-1.awsapprunner.com/table";

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final rawId = prefs.get('patient_id');
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
      final res = await http.get(Uri.parse("$_baseUrl/users"));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final List<dynamic> data = decoded is Map ? (decoded['data'] ?? []) : decoded;
        final record = data.firstWhere(
          (e) {
            final id = e["user_id"] ?? e["patient_id"];
            if (id == null) return false;
            return id is int
                ? id == patientId
                : id.toString() == patientId.toString();
          },
          orElse: () => null,
        );
        if (mounted) {
          setState(() {
            _user = record != null ? Map<String, dynamic>.from(record) : null;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() { _loading = false; _errorMsg = "Failed to load profile"; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errorMsg = "Network error: $e"; });
    }
  }

  Widget _infoRow(IconData icon, String label, String? value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
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
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value ?? "—",
                    style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return "?";
    final parts = name.trim().split(" ");
    if (parts.length >= 2) {
      return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final username = _user?["username"] as String?;
    final email = _user?["email"] as String?;
    final role = _user?["role"] as String?;
    final status = _user?["status"] as String?;
    final createdOn = _user?["created_on"] as String?;
    final userId = _user?["user_id"]?.toString() ?? _user?["patient_id"]?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Settings",
            onPressed: () => Navigator.pushNamed(context, "/settings"),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
              ? Center(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red)))
              : _user == null
                  ? const Center(child: Text("Profile not found"))
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          // ── Gradient header ──────────────────────────
                          Container(
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 44,
                                  backgroundColor: Colors.white.withOpacity(0.25),
                                  child: Text(
                                    _initials(username),
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  username ?? "Unknown",
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email ?? "",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (role != null)
                                      _badgeChip(
                                        role.toUpperCase(),
                                        Colors.white,
                                      ),
                                    if (status != null) ...[
                                      const SizedBox(width: 8),
                                      _badgeChip(
                                        status.toUpperCase(),
                                        status.toLowerCase() == "active"
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // ── Info rows ─────────────────────────────────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                            child: Column(
                              children: [
                                _infoRow(Icons.badge_outlined, "Patient ID", userId),
                                _infoRow(Icons.person_outline, "Username", username),
                                _infoRow(Icons.email_outlined, "Email", email),
                                _infoRow(Icons.verified_user_outlined, "Role", role),
                                _infoRow(Icons.circle_outlined, "Status", status),
                                _infoRow(Icons.calendar_today_outlined, "Member Since", createdOn),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
