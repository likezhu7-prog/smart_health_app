import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ui/app_theme.dart';

class EmergencySosScreen extends StatefulWidget {
  const EmergencySosScreen({super.key});

  @override
  State<EmergencySosScreen> createState() => _EmergencySosScreenState();
}

class _EmergencySosScreenState extends State<EmergencySosScreen> {
  String _bloodType = "";
  String _allergies = "";
  String _contactName = "";
  String _contactPhone = "";
  int? _patientId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawId = prefs.get("patient_id");
    _patientId = int.tryParse(rawId?.toString() ?? '');
    setState(() {
      _bloodType = prefs.getString("emergency_blood_type_$_patientId") ?? "";
      _allergies = prefs.getString("emergency_allergies_$_patientId") ?? "";
      _contactName = prefs.getString("emergency_contact_name_$_patientId") ?? "";
      _contactPhone = prefs.getString("emergency_contact_phone_$_patientId") ?? "";
    });
  }

  Future<void> _save() async {
    if (_patientId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("emergency_blood_type_$_patientId", _bloodType);
    await prefs.setString("emergency_allergies_$_patientId", _allergies);
    await prefs.setString("emergency_contact_name_$_patientId", _contactName);
    await prefs.setString("emergency_contact_phone_$_patientId", _contactPhone);
  }

  void _editField(String title, String current, IconData icon, ValueChanged<String> onSave) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Edit $title"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: title,
            prefixIcon: Icon(icon, color: Colors.red.shade700),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () {
              Navigator.pop(ctx);
              onSave(ctrl.text.trim());
              _save();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _callEmergency() async {
    final uri = Uri.parse("tel:911");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cannot launch phone dialer")),
        );
      }
    }
  }

  Widget _infoCard(IconData icon, String label, String value, VoidCallback onEdit) {
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.08),
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
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: Colors.red.shade700),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11, color: Colors.red.shade300, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? "Tap to set" : value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: value.isEmpty ? AppColors.textMuted : AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 18, color: Colors.red.shade300),
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
            backgroundColor: Colors.red.shade700,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text("Emergency SOS",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade700, Colors.red.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.emergency_outlined, size: 48, color: Colors.white54),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Warning banner ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_outlined, color: Colors.red.shade700, size: 24),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Keep this information up to date. It could save your life in an emergency.",
                            style: TextStyle(fontSize: 13, color: AppColors.textDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Section header ─────────────────────────────
                  const Text("Medical Information",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: AppColors.textMuted, letterSpacing: 0.8)),
                  const SizedBox(height: 12),

                  _infoCard(
                    Icons.bloodtype_outlined,
                    "Blood Type",
                    _bloodType,
                    () => _editField("Blood Type", _bloodType, Icons.bloodtype_outlined,
                        (v) => setState(() => _bloodType = v)),
                  ),
                  _infoCard(
                    Icons.warning_amber_outlined,
                    "Allergies",
                    _allergies,
                    () => _editField("Allergies", _allergies, Icons.warning_amber_outlined,
                        (v) => setState(() => _allergies = v)),
                  ),

                  const SizedBox(height: 8),
                  const Text("Emergency Contact",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: AppColors.textMuted, letterSpacing: 0.8)),
                  const SizedBox(height: 12),

                  _infoCard(
                    Icons.person_outlined,
                    "Contact Name",
                    _contactName,
                    () => _editField("Contact Name", _contactName, Icons.person_outlined,
                        (v) => setState(() => _contactName = v)),
                  ),
                  _infoCard(
                    Icons.phone_outlined,
                    "Contact Phone",
                    _contactPhone,
                    () => _editField("Contact Phone", _contactPhone, Icons.phone_outlined,
                        (v) => setState(() => _contactPhone = v)),
                  ),

                  const SizedBox(height: 32),

                  // ── Call 911 button ────────────────────────────
                  GestureDetector(
                    onTap: _callEmergency,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade700, Colors.red.shade500],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_outlined, color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Text(
                            "CALL EMERGENCY (911)",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
