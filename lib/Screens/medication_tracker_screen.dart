import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../ui/app_theme.dart';

class MedicationTrackerScreen extends StatefulWidget {
  const MedicationTrackerScreen({super.key});

  @override
  State<MedicationTrackerScreen> createState() => _MedicationTrackerScreenState();
}

class _MedicationTrackerScreenState extends State<MedicationTrackerScreen> {
  List<Map<String, dynamic>> _meds = [];
  int? _patientId;

  // Form controllers
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _freqCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMeds();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _freqCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeds() async {
    final prefs = await SharedPreferences.getInstance();
    final rawId = prefs.get("patient_id");
    _patientId = int.tryParse(rawId?.toString() ?? '');
    if (_patientId == null) return;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastReset = prefs.getString("lastResetDate_$_patientId") ?? "";
    final raw = prefs.getString("medications_$_patientId") ?? "[]";
    List<Map<String, dynamic>> meds =
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();

    if (lastReset != today) {
      for (final m in meds) {
        m["takenToday"] = false;
      }
      await prefs.setString("medications_$_patientId", jsonEncode(meds));
      await prefs.setString("lastResetDate_$_patientId", today);
    }

    if (mounted) setState(() => _meds = meds);
  }

  Future<void> _saveMeds() async {
    if (_patientId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("medications_$_patientId", jsonEncode(_meds));
  }

  Future<void> _addMed() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final med = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "name": name,
      "dosage": _dosageCtrl.text.trim(),
      "frequency": _freqCtrl.text.trim(),
      "time": _timeCtrl.text.trim(),
      "takenToday": false,
    };
    setState(() => _meds.add(med));
    await _saveMeds();
    _nameCtrl.clear();
    _dosageCtrl.clear();
    _freqCtrl.clear();
    _timeCtrl.clear();
  }

  Future<void> _toggleTaken(int index) async {
    setState(() => _meds[index]["takenToday"] = !(_meds[index]["takenToday"] as bool));
    await _saveMeds();
  }

  Future<void> _deleteMed(int index) async {
    setState(() => _meds.removeAt(index));
    await _saveMeds();
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Add Medication",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 16),
            _field(_nameCtrl, "Medication Name", Icons.medication_outlined),
            const SizedBox(height: 10),
            _field(_dosageCtrl, "Dosage (e.g. 10mg)", Icons.colorize_outlined),
            const SizedBox(height: 10),
            _field(_freqCtrl, "Frequency (e.g. Once daily)", Icons.repeat),
            const SizedBox(height: 10),
            _field(_timeCtrl, "Time (e.g. 8:00 AM)", Icons.access_time),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _addMed();
                },
                child: const Text("Add Medication"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
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
            flexibleSpace: FlexibleSpaceBar(
              title: const Text("Medications", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.medication_outlined, size: 48, color: Colors.white54),
                ),
              ),
            ),
          ),
          _meds.isEmpty
              ? const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.medication_outlined, size: 64, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text("No medications yet", style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
                        SizedBox(height: 4),
                        Text("Tap + to add one", style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _medCard(i),
                      childCount: _meds.length,
                    ),
                  ),
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _medCard(int i) {
    final med = _meds[i];
    final taken = med["takenToday"] as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: GestureDetector(
          onTap: () => _toggleTaken(i),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: taken ? Colors.green.shade50 : AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              taken ? Icons.check_circle : Icons.circle_outlined,
              color: taken ? Colors.green : AppColors.primary,
              size: 24,
            ),
          ),
        ),
        title: Text(
          med["name"] as String,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.textDark,
            decoration: taken ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          "${med["dosage"]} · ${med["frequency"]} · ${med["time"]}",
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _deleteMed(i),
        ),
      ),
    );
  }
}
