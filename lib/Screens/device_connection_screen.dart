import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../ui/app_theme.dart';
import '../services/e_hospital_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Device Manager — lists all patients, shows Apple Watch sync status, lets
// any patient's wearable data be simulated (7 realistic days → eHospital DB).
// ─────────────────────────────────────────────────────────────────────────────

class DeviceConnectionScreen extends StatefulWidget {
  const DeviceConnectionScreen({super.key});

  @override
  State<DeviceConnectionScreen> createState() => _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState extends State<DeviceConnectionScreen> {
  bool _loading = true;
  String? _errorMsg;
  List<_PatientDevice> _patients = [];

  static const String _baseUrl = "https://aetab8pjmb.us-east-1.awsapprunner.com/table";

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final results = await Future.wait([
        http.get(Uri.parse("$_baseUrl/users")),
        http.get(Uri.parse("$_baseUrl/wearable_vitals")),
      ]);

      if (results[0].statusCode != 200) {
        setState(() { _loading = false; _errorMsg = "Failed to load patients"; });
        return;
      }

      final usersDecoded = jsonDecode(results[0].body);
      final List<dynamic> users =
          usersDecoded is Map ? (usersDecoded['data'] ?? []) : usersDecoded;

      // Build per-patient sync stats from wearable_vitals
      final Map<String, String> latestSync = {};
      final Map<String, int> recordCounts = {};
      if (results[1].statusCode == 200) {
        final vitalsDecoded = jsonDecode(results[1].body);
        final List<dynamic> vitals =
            vitalsDecoded is Map ? (vitalsDecoded['data'] ?? []) : vitalsDecoded;
        for (final v in vitals) {
          final pid = (v['patient_id'] ?? '').toString();
          recordCounts[pid] = (recordCounts[pid] ?? 0) + 1;
          final ts = (v['timestamp'] as String?) ?? '';
          if (ts.isNotEmpty) {
            if (!latestSync.containsKey(pid) || ts.compareTo(latestSync[pid]!) > 0) {
              latestSync[pid] = ts;
            }
          }
        }
      }

      final list = users.map((u) {
        final id = (u['user_id'] ?? u['patient_id'] ?? '').toString();
        return _PatientDevice(
          patientId: id,
          name: (u['username'] as String? ?? '').isEmpty
              ? 'Patient $id'
              : u['username'] as String,
          email: u['email'] as String? ?? '',
          lastSync: latestSync[id],
          recordCount: recordCounts[id] ?? 0,
        );
      }).toList()
        ..sort((a, b) =>
            (int.tryParse(a.patientId) ?? 0)
                .compareTo(int.tryParse(b.patientId) ?? 0));

      setState(() { _patients = list; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _errorMsg = 'Error: $e'; });
    }
  }

  void _simulateForPatient(_PatientDevice patient) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SimulateDialog(patient: patient),
    ).then((_) => _loadPatients()); // refresh counts after simulation
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Gradient header ─────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                "Device Manager",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.watch_outlined, size: 48, color: Colors.white54),
                ),
              ),
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          _loading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()))
              : _errorMsg != null
                  ? SliverFillRemaining(
                      child: Center(
                        child: Text(_errorMsg!,
                            style: const TextStyle(color: Colors.red)),
                      ))
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _infoBanner(),
                          const SizedBox(height: 4),
                          _sectionHeader("${_patients.length} Patients in eHospital DB"),
                          const SizedBox(height: 10),
                          ..._patients.map((p) => _patientCard(p)),
                        ]),
                      ),
                    ),
        ],
      ),
    );
  }

  // ── Info banner ──────────────────────────────────────────────────────────
  Widget _infoBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Apple Watch → eHospital",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
                SizedBox(height: 4),
                Text(
                  "On a real device: patient logs in and taps "
                  "\"Sync Apple Watch\" to push live Health data.\n"
                  "For demo/testing: tap Simulate to generate 7 days "
                  "of realistic wearable data for any patient.",
                  style: TextStyle(fontSize: 12, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted),
    );
  }

  // ── Per-patient card ─────────────────────────────────────────────────────
  Widget _patientCard(_PatientDevice p) {
    final hasSynced = p.lastSync != null;
    final statusColor = hasSynced ? Colors.green : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.07),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Watch icon with status color
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.watch_outlined, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),

          // Patient info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      p.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark),
                    ),
                  ),
                  _statusChip(hasSynced ? "CONNECTED" : "NO DATA", statusColor),
                ]),
                const SizedBox(height: 2),
                Text(
                  "ID: ${p.patientId}  ·  ${p.email}",
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.history, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    hasSynced ? _formatSync(p.lastSync!) : "Never synced",
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  if (p.recordCount > 0) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.storage_outlined,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Text(
                      "${p.recordCount} records",
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary),
                    ),
                  ],
                ]),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Simulate button
          ElevatedButton(
            onPressed: () => _simulateForPatient(p),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.watch_outlined, color: Colors.white, size: 16),
                SizedBox(height: 2),
                Text(
                  "Simulate",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  String _formatSync(String isoStr) {
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return "Just now";
      if (diff.inHours < 1) return "${diff.inMinutes}m ago";
      if (diff.inDays < 1) return "${diff.inHours}h ago";
      return "${diff.inDays}d ago";
    } catch (_) {
      return isoStr;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress dialog — manages its own upload lifecycle
// ─────────────────────────────────────────────────────────────────────────────

class _SimulateDialog extends StatefulWidget {
  final _PatientDevice patient;
  const _SimulateDialog({required this.patient});

  @override
  State<_SimulateDialog> createState() => _SimulateDialogState();
}

class _SimulateDialogState extends State<_SimulateDialog> {
  int _progress = 0;
  bool _done = false;
  String? _error;
  static const int _total = 7;

  @override
  void initState() {
    super.initState();
    _runSimulation();
  }

  Future<void> _runSimulation() async {
    final rng = Random();
    try {
      for (int day = _total - 1; day >= 0; day--) {
        // Spread timestamps across the past 7 days, each at 08:00
        final date = DateTime.now().subtract(Duration(days: day));
        final ts = DateTime(date.year, date.month, date.day, 8, 0, 0);

        final steps   = 4800 + rng.nextInt(10200); // 4800 – 15000
        final hr      = 58   + rng.nextInt(43);    // 58 – 100
        final cal     = 180  + rng.nextInt(421);   // 180 – 600
        final sleepHr = 5    + rng.nextInt(4);     // 5 – 8

        await EHospitalService.sendWearableVitals(
          patientId: widget.patient.patientId,
          heartRate: hr,
          steps: steps,
          calories: cal,
          sleep: sleepHr,
        );

        if (mounted) setState(() => _progress = _total - day);
        await Future.delayed(const Duration(milliseconds: 350));
      }

      if (mounted) setState(() => _done = true);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: const BoxDecoration(
              color: AppColors.primarySoft, shape: BoxShape.circle),
          child: const Icon(Icons.watch_outlined,
              size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        const Text("Simulating Data",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Patient: ${widget.patient.name}",
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark),
          ),
          const SizedBox(height: 4),
          const Text(
            "Apple Watch  →  Apple Health  →  eHospital DB",
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),

          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _done ? 1.0 : _progress / _total,
                minHeight: 10,
                backgroundColor: AppColors.primarySoft,
                valueColor: AlwaysStoppedAnimation<Color>(
                    _done ? Colors.green : AppColors.primary),
              ),
            ),
            const SizedBox(height: 12),
            // Day-by-day indicator
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(_total, (i) {
                final dayNum = i + 1;
                final uploaded = i < _progress;
                final current = i == _progress && !_done;
                return _DayChip(
                  day: dayNum,
                  uploaded: uploaded,
                  current: current,
                );
              }),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Icon(
                _done
                    ? Icons.check_circle
                    : Icons.cloud_upload_outlined,
                size: 16,
                color: _done ? Colors.green : AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _done
                    ? "✓ ${_total} days uploaded to eHospital!"
                    : "Uploading day $_progress of $_total…",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _done ? Colors.green : AppColors.primary,
                ),
              ),
            ]),
          ],
        ],
      ),
      actions: _error != null
          ? [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close")),
            ]
          : null,
    );
  }
}

class _DayChip extends StatelessWidget {
  final int day;
  final bool uploaded;
  final bool current;
  const _DayChip({required this.day, required this.uploaded, required this.current});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    if (uploaded) {
      bg = Colors.green.withOpacity(0.15);
      fg = Colors.green;
    } else if (current) {
      bg = AppColors.primarySoft;
      fg = AppColors.primary;
    } else {
      bg = Colors.grey.shade100;
      fg = Colors.grey.shade400;
    }

    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: uploaded
            ? Icon(Icons.check, size: 14, color: fg)
            : current
                ? SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: fg))
                : Text(
                    "D$day",
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: fg),
                  ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple data model
// ─────────────────────────────────────────────────────────────────────────────

class _PatientDevice {
  final String patientId;
  final String name;
  final String email;
  final String? lastSync;
  final int recordCount;

  const _PatientDevice({
    required this.patientId,
    required this.name,
    required this.email,
    required this.lastSync,
    required this.recordCount,
  });
}
