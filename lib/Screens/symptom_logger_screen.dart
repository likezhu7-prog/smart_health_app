import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../ui/app_theme.dart';

class SymptomLoggerScreen extends StatefulWidget {
  const SymptomLoggerScreen({super.key});

  @override
  State<SymptomLoggerScreen> createState() => _SymptomLoggerScreenState();
}

class _SymptomLoggerScreenState extends State<SymptomLoggerScreen> {
  List<Map<String, dynamic>> _symptoms = [];

  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  double _severity = 3;

  @override
  void initState() {
    super.initState();
    _loadSymptoms();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSymptoms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("symptoms") ?? "[]";
    final list = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    list.sort((a, b) => (b["timestamp"] as String).compareTo(a["timestamp"] as String));
    if (mounted) setState(() => _symptoms = list);
  }

  Future<void> _saveSymptoms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("symptoms", jsonEncode(_symptoms));
  }

  Future<void> _addSymptom() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final entry = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "name": name,
      "severity": _severity.round(),
      "notes": _notesCtrl.text.trim(),
      "timestamp": DateTime.now().toIso8601String(),
    };
    setState(() {
      _symptoms.insert(0, entry);
    });
    await _saveSymptoms();
    _nameCtrl.clear();
    _notesCtrl.clear();
    setState(() => _severity = 3);
  }

  Future<void> _deleteSymptom(int index) async {
    setState(() => _symptoms.removeAt(index));
    await _saveSymptoms();
  }

  Color _severityColor(int sev) {
    if (sev <= 1) return Colors.green;
    if (sev == 2) return Colors.lightGreen;
    if (sev == 3) return Colors.orange;
    if (sev == 4) return Colors.deepOrange;
    return Colors.red;
  }

  String _severityLabel(int sev) {
    switch (sev) {
      case 1: return "Very Mild";
      case 2: return "Mild";
      case 3: return "Moderate";
      case 4: return "Severe";
      default: return "Very Severe";
    }
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? "PM" : "AM";
      final min = dt.minute.toString().padLeft(2, "0");
      return "${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$min $ampm";
    } catch (_) {
      return iso;
    }
  }

  void _showAddSheet() {
    setState(() {
      _severity = 3;
      _nameCtrl.clear();
      _notesCtrl.clear();
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Log Symptom",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Symptom Name",
                  prefixIcon: Icon(Icons.sick_outlined, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Severity", style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _severityColor(_severity.round()).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${_severity.round()} · ${_severityLabel(_severity.round())}",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _severityColor(_severity.round()),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _severity,
                min: 1,
                max: 5,
                divisions: 4,
                activeColor: _severityColor(_severity.round()),
                onChanged: (v) => setModalState(() => _severity = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Notes (optional)",
                  prefixIcon: Icon(Icons.notes_outlined, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addSymptom();
                  },
                  child: const Text("Log Symptom"),
                ),
              ),
            ],
          ),
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
            flexibleSpace: FlexibleSpaceBar(
              title: const Text("Symptom Log",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.sick_outlined, size: 48, color: Colors.white54),
                ),
              ),
            ),
          ),
          _symptoms.isEmpty
              ? const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sick_outlined, size: 64, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text("No symptoms logged", style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
                        SizedBox(height: 4),
                        Text("Tap + to log one", style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _symptomCard(i),
                      childCount: _symptoms.length,
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

  Widget _symptomCard(int i) {
    final s = _symptoms[i];
    final sev = (s["severity"] as int);
    final color = _severityColor(sev);
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(s["name"] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "${_severityLabel(sev)} ($sev/5)",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((s["notes"] as String).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(s["notes"] as String,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
            const SizedBox(height: 4),
            Text(_formatTime(s["timestamp"] as String),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _deleteSymptom(i),
        ),
      ),
    );
  }
}
