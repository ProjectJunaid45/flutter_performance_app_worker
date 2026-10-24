import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sing_in.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  int _currentTabIndex = 0; // 0: Home, 1: 100-Mark Scorecard, 2: History, 3: Profile
  bool _isLoading = true;

  String _currentWorker = "MALIK10";
  String _workerFullName = "malik";
  String _workerPhone = "-";

  // Scorecard Navigator States (Month & Year)
  int _scoreSelYear = 2026;
  int _scoreSelMonth = 10;
  bool _isScoreYearlyMode = false;

  // Real 100-Mark Factory Evaluation Metrics
  int _score100 = 0;
  double _myRating = 0.0;
  String _ratingTag = "NOT EVALUATED";
  String _ratingComment = "Awaiting supervisor quality review.";

  // 7 Quality & Attendance Parameters Breakdown
  int _wiringMarks = 0;
  int _dressingMarks = 0;
  int _attendanceMarks = 0;
  int _ferruleMarks = 0;
  int _plcSignalMarks = 0;
  int _mountingMarks = 0;
  int _safetyQcMarks = 0;

  List<Map<String, dynamic>> _myAllJobs = [];
  List<Map<String, dynamic>> _myAuditHistoryList = [];
  String _searchQuery = '';
  String _activeFilter = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _historySearchCtrl = TextEditingController();
  String _historySearchQuery = '';

  // History Tab Filter States (Month & Year)
  int _historySelYear = 2026;
  int _historySelMonth = 10;
  bool _isHistoryYearlyMode = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _scoreSelYear = now.year;
    _scoreSelMonth = now.month;
    _historySelYear = now.year;
    _historySelMonth = now.month;
    _loadWorkerSession();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _historySearchCtrl.dispose();
    super.dispose();
  }

  static String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return (month >= 1 && month <= 12) ? months[month - 1] : 'Jan';
  }

  static String _calculateTimeAgo(String dateString) {
    try {
      final now = DateTime.now();
      DateTime? parsedDate;

      final parts = dateString.trim().split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final d = int.tryParse(parts[0]);
        final mName = parts[1].toLowerCase();
        final y = int.tryParse(parts[2]);

        const mList = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
        final m = mList.indexOf(mName) + 1;

        if (d != null && m > 0 && y != null) {
          parsedDate = DateTime(y, m, d);
        }
      }

      parsedDate ??= DateTime.tryParse(dateString);

      if (parsedDate == null) {
        return "Delivered Log";
      }

      int monthDiff = (now.year - parsedDate.year) * 12 + (now.month - parsedDate.month);
      if (monthDiff <= 0) {
        int dayDiff = now.difference(parsedDate).inDays;
        if (dayDiff <= 0) return "Completed Today";
        if (dayDiff == 1) return "Completed Yesterday";
        return "Completed this month ($dayDiff days ago)";
      } else if (monthDiff == 1) {
        return "Completed 1 month ago";
      } else {
        return "Completed $monthDiff months ago";
      }
    } catch (_) {
      return "Delivered Log";
    }
  }

  static Map<String, int> _extractBreakdownMap(String specs) {
    int w = 0, d = 0, a = 0, f = 0, p = 0, m = 0, s = 0;
    final wMatch = RegExp(r'W:(\d+)').firstMatch(specs);
    final dMatch = RegExp(r'D:(\d+)').firstMatch(specs);
    final aMatch = RegExp(r'A:(\d+)').firstMatch(specs);
    final fMatch = RegExp(r'F:(\d+)').firstMatch(specs);
    final pMatch = RegExp(r'P:(\d+)').firstMatch(specs);
    final mMatch = RegExp(r'M:(\d+)').firstMatch(specs);
    final sMatch = RegExp(r'S:(\d+)').firstMatch(specs);

    if (wMatch != null) w = int.tryParse(wMatch.group(1)!) ?? 0;
    if (dMatch != null) d = int.tryParse(dMatch.group(1)!) ?? 0;
    if (aMatch != null) a = int.tryParse(aMatch.group(1)!) ?? 0;
    if (fMatch != null) f = int.tryParse(fMatch.group(1)!) ?? 0;
    if (pMatch != null) p = int.tryParse(pMatch.group(1)!) ?? 0;
    if (mMatch != null) m = int.tryParse(mMatch.group(1)!) ?? 0;
    if (sMatch != null) s = int.tryParse(sMatch.group(1)!) ?? 0;

    return {'Wiring': w, 'Dressing': d, 'Attendance': a, 'Ferrule': f, 'PLC': p, 'Mounting': m, 'Safety': s};
  }

  static Map<String, dynamic> _compareScoreWithPrevious(Map<String, dynamic> currentJob, List<Map<String, dynamic>> allCompleted) {
    final curSpecs = (currentJob['specs_detail'] ?? '').toString();
    final curBadge = RegExp(r'\[SCORE:\s*(\d+)').firstMatch(curSpecs);
    final int curScore = curBadge != null ? (int.tryParse(curBadge.group(1)!) ?? 0) : 0;

    final curMap = _extractBreakdownMap(curSpecs);

    final curIndex = allCompleted.indexOf(currentJob);
    Map<String, dynamic>? prevJob;
    if (curIndex != -1 && curIndex + 1 < allCompleted.length) {
      prevJob = allCompleted[curIndex + 1];
    }

    if (prevJob == null || curScore == 0) {
      return {
        'diff': 0,
        'hasPrev': false,
        'curScore': curScore,
        'prevScore': 0,
        'improved': <String>[],
        'dropped': <String>[],
        'summary': 'First audited record for comparison.',
      };
    }

    final prevSpecs = (prevJob['specs_detail'] ?? '').toString();
    final prevBadge = RegExp(r'\[SCORE:\s*(\d+)').firstMatch(prevSpecs);
    final int prevScore = prevBadge != null ? (int.tryParse(prevBadge.group(1)!) ?? 0) : 0;
    final prevMap = _extractBreakdownMap(prevSpecs);

    final int diff = curScore - prevScore;
    final List<String> improved = [];
    final List<String> dropped = [];

    curMap.forEach((key, curVal) {
      final prevVal = prevMap[key] ?? 0;
      final change = curVal - prevVal;
      if (change > 0) {
        improved.add("$key (+$change)");
      } else if (change < 0) {
        dropped.add("$key ($change)");
      }
    });

    String summary;
    if (diff > 0) {
      summary = "Increased by +$diff pts mainly due to ${improved.isNotEmpty ? improved.join(', ') : 'overall quality'}";
    } else if (diff < 0) {
      summary = "Decreased by $diff pts due to ${dropped.isNotEmpty ? dropped.join(', ') : 'deductions'}";
    } else {
      summary = "Score maintained steadily at $curScore pts.";
    }

    return {
      'diff': diff,
      'hasPrev': true,
      'curScore': curScore,
      'prevScore': prevScore,
      'improved': improved,
      'dropped': dropped,
      'summary': summary,
    };
  }

  Future<void> _loadWorkerSession() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUser = prefs.getString('logged_worker_username') ??
          prefs.getString('logged_operator_username') ??
          'MALIK10';

      _currentWorker = savedUser.trim().toUpperCase();

      // 1. Worker Profile Data
      final workerData = await _supabase
          .from('workers')
          .select()
          .ilike('username', _currentWorker)
          .maybeSingle();

      if (workerData != null) {
        _workerFullName = (workerData['full_name'] ?? _currentWorker).toString();
        _workerPhone = (workerData['phone'] ?? '-').toString();
        _score100 = (workerData['score_100'] as num?)?.toInt() ?? 0;

        // Exact 5-star rating from DB or formula
        final rawRating = (workerData['rating'] as num?)?.toDouble() ?? 0.0;
        if (rawRating > 0.0) {
          _myRating = rawRating;
        } else if (_score100 > 0) {
          _myRating = (_score100 / 20.0).clamp(1.0, 5.0);
        } else {
          _myRating = 0.0;
        }

        _ratingTag = (workerData['rating_tag'] ?? 'NOT EVALUATED').toString();
        _ratingComment = (workerData['rating_comment'] ?? 'Awaiting supervisor quality review.').toString();

        final rawBreakdown = (workerData['qc_breakdown'] ?? '').toString();
        final map = _extractBreakdownMap(rawBreakdown);
        _wiringMarks = map['Wiring'] ?? 0;
        _dressingMarks = map['Dressing'] ?? 0;
        _attendanceMarks = map['Attendance'] ?? 0;
        _ferruleMarks = map['Ferrule'] ?? 0;
        _plcSignalMarks = map['PLC'] ?? 0;
        _mountingMarks = map['Mounting'] ?? 0;
        _safetyQcMarks = map['Safety'] ?? 0;
      }

      // 2. Worker Audits History Table Data
      try {
        final historyRes = await _supabase
            .from('worker_audits')
            .select()
            .ilike('username', _currentWorker)
            .order('audit_year', ascending: false)
            .order('audit_month', ascending: false);
        _myAuditHistoryList = List<Map<String, dynamic>>.from(historyRes);
      } catch (_) {}

      // 3. Assigned Production Jobs (No Quotes)
      final allJobs = await _supabase
          .from('job_cards')
          .select()
          .order('id', ascending: false);

      final filtered = List<Map<String, dynamic>>.from(allJobs).where((j) {
        final status = (j['status'] ?? '').toString().toUpperCase().trim();
        if (status == 'QUOTATION' || status == 'QUOTE') return false;

        final assigned = (j['assigned_to'] ?? '').toString().trim().toUpperCase();
        final specs = (j['specs_detail'] ?? '').toString().toUpperCase();

        final bool isDirectAssigned = (assigned == _currentWorker);
        final bool isPreviouslyAssigned = specs.contains("[PREV_WORKER:$_currentWorker]") || specs.contains("FROM:$_currentWorker");

        return isDirectAssigned || isPreviouslyAssigned;
      }).toList();

      if (mounted) {
        setState(() {
          _myAllJobs = filtered;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignOut() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C2232),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 8),
            Text("Sign Out", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("Kya aap session close karke login screen par jana chahte hain?", style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sign Out", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('logged_worker_username');
        await prefs.remove('logged_operator_username');
        await _supabase.auth.signOut().catchError((_) {});
      } catch (_) {}

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SignInScreen()),
          (route) => false,
        );
      }
    }
  }

  static String _extractCleanScope(String specs) {
    return specs
        .replaceAll(RegExp(r'\[QUOTE:.*?\]'), '')
        .replaceAll(RegExp(r'\[PO:.*?\]'), '')
        .replaceAll(RegExp(r'\[BY:.*?\]'), '')
        .replaceAll(RegExp(r'\[WORKER:.*?\]'), '')
        .replaceAll(RegExp(r'\[PREV_WORKER:.*?\]'), '')
        .replaceAll(RegExp(r'\[TRANSFER:.*?\]'), '')
        .replaceAll(RegExp(r'\[SCORE:.*?\]'), '')
        .replaceAll(RegExp(r'\[DONE:.*?\]'), '')
        .trim();
  }

  void _showJobDetailsBottomSheet(Map<String, dynamic> job) {
    final jobNo = (job['job_no'] ?? '-').toString();
    final client = (job['client'] ?? '-').toString();
    final panelType = (job['panel_type'] ?? '').toString().replaceAll('[PANEL]', '').replaceAll(RegExp(r'\[ITEM:.*?\]'), '').trim();
    final stage = (job['stage'] ?? 'Fabrication & Layout').toString();
    final status = (job['status'] ?? '').toString().toUpperCase();
    final startDate = (job['start_date'] ?? '-').toString();
    final targetDate = (job['target_date'] ?? '-').toString();
    final scope = _extractCleanScope((job['specs_detail'] ?? '').toString());
    final double progress = (job['progress'] as num?)?.toDouble() ?? 0.25;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF091722),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF244866), borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(jobNo, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.w900)),
                      Text(client, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF0284C7)),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF193B54)),
              const SizedBox(height: 8),
              _buildDetailInfoRow("Panel Type:", panelType),
              const SizedBox(height: 6),
              _buildDetailInfoRow("Current Stage:", stage),
              const SizedBox(height: 6),
              _buildDetailInfoRow("Start Date:", startDate),
              const SizedBox(height: 6),
              _buildDetailInfoRow("Target Delivery:", targetDate, isAlert: true),
              const SizedBox(height: 14),
              const Text("Assembly Scope & Instructions:", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C2030),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E4362)),
                ),
                child: Text(
                  scope.isNotEmpty ? scope : "Standard assembly and wiring guidelines applicable.",
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Progress Tracker:", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                  Text("${(progress * 100).toInt()}% Done", style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFF132A3E),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Close Window", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHistoryInspectionModal(Map<String, dynamic> job, Map<String, dynamic> comparison) {
    final jobNo = (job['job_no'] ?? '-').toString();
    final client = (job['client'] ?? '-').toString();
    final panelType = (job['panel_type'] ?? '').toString().replaceAll('[PANEL]', '').replaceAll(RegExp(r'\[ITEM:.*?\]'), '').trim();
    final targetDate = (job['target_date'] ?? '-').toString();
    final startDate = (job['start_date'] ?? '-').toString();
    final scope = _extractCleanScope((job['specs_detail'] ?? '').toString());
    final timeAgoText = _calculateTimeAgo(targetDate != '-' ? targetDate : startDate);

    final int diff = comparison['diff'] ?? 0;
    final int curScore = comparison['curScore'] ?? 0;
    final int prevScore = comparison['prevScore'] ?? 0;
    final List<String> improved = List<String>.from(comparison['improved'] ?? []);
    final List<String> dropped = List<String>.from(comparison['dropped'] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF091722),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF244866), borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("$jobNo Audit Analysis", style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.w900)),
                      Text(client, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Text(
                      "$curScore/100",
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFFE88226)),
                  const SizedBox(width: 5),
                  Text(timeAgoText, style: const TextStyle(color: Color(0xFFE88226), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF193B54)),
              const SizedBox(height: 8),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C2232),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: diff > 0
                        ? const Color(0xFF10B981).withOpacity(0.6)
                        : (diff < 0 ? const Color(0xFFEF4444).withOpacity(0.6) : const Color(0xFF0284C7).withOpacity(0.6)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Difference from Previous Panel:", style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: (diff > 0 ? const Color(0xFF10B981) : (diff < 0 ? const Color(0xFFEF4444) : Colors.grey)).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            diff > 0 ? "+$diff pts ▲" : (diff < 0 ? "$diff pts ▼" : "0 pts (Same)"),
                            style: TextStyle(
                              color: diff > 0 ? const Color(0xFF10B981) : (diff < 0 ? const Color(0xFFEF4444) : Colors.white70),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Current: $curScore/100  |  Previous: $prevScore/100",
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (improved.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("🟢 Points Gained In: ", style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(improved.join(', '), style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                            ),
                          ],
                        ),
                      ),
                    if (dropped.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("🔴 Points Deducted In: ", style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(dropped.join(', '), style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                          ),
                        ],
                      ),
                    if (improved.isEmpty && dropped.isEmpty)
                      const Text(
                        "Sabhi parameters pichhle panel ke barabar hain.",
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              _buildDetailInfoRow("Panel Type:", panelType),
              const SizedBox(height: 4),
              _buildDetailInfoRow("Production Started:", startDate),
              const SizedBox(height: 4),
              _buildDetailInfoRow("Delivered Date:", targetDate),
              const SizedBox(height: 8),

              if (scope.isNotEmpty) ...[
                const Text("Scope of Work Summary:", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C2030),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E4362)),
                  ),
                  child: Text(scope, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3)),
                ),
                const SizedBox(height: 12),
              ],

              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Close Log", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildDetailInfoRow(String label, String value, {bool isAlert = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5))),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isAlert ? const Color(0xFFE88226) : Colors.white,
              fontSize: 11.5,
              fontWeight: isAlert ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07121A),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0C2232),
        elevation: 0.5,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF0284C7), width: 1.2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  'assets/images/nextgen_logo_1.jpg',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.precision_manufacturing_rounded, size: 20, color: Color(0xFF0284C7)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Floor Operations", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                  Text("Builder: $_currentWorker", style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            // ⭐ 5-STAR HIGHLIGHT BADGE IN APPBAR
            GestureDetector(
              onTap: () => setState(() => _currentTabIndex = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0C2232)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE88226), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE88226).withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFE88226), size: 16),
                    const SizedBox(width: 3),
                    Text(
                      _myRating > 0 ? _myRating.toStringAsFixed(1) : "0.0",
                      style: const TextStyle(
                        color: Color(0xFFE88226),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 1.2,
                      height: 12,
                      color: const Color(0xFF193B54),
                    ),
                    Text(
                      "$_score100/100",
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE88226)))
          : IndexedStack(
              index: _currentTabIndex,
              children: [
                _buildHomeTab(),
                _build100MarkScorecardTab(),
                _buildHistoryTab(),
                _buildProfileTab(),
              ],
            ),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF091824),
          border: Border(top: BorderSide(color: Color(0xFF193B54), width: 1.2)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) => setState(() => _currentTabIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF38BDF8),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10.5),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.fact_check_outlined),
              activeIcon: Icon(Icons.fact_check_rounded, color: Color(0xFF10B981)),
              label: "My Score (100)",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_toggle_off_rounded),
              activeIcon: Icon(Icons.history_rounded, color: Color(0xFF38BDF8)),
              label: "History",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: "Profile",
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 0: HOME (ACTIVE FLOOR PRODUCTION - NO QUOTES)
  // =========================================================================
  Widget _buildHomeTab() {
    final activeOnlyJobs = _myAllJobs.where((j) => (j['assigned_to'] ?? '').toString().toUpperCase() == _currentWorker).toList();
    final assignedCount = activeOnlyJobs.length;
    final inProgressCount = activeOnlyJobs.where((j) {
      final s = (j['status'] ?? '').toString().toUpperCase();
      return s == 'RUNNING' || s == 'TESTING' || s == 'PENDING';
    }).length;
    final completedCount = activeOnlyJobs.where((j) {
      final s = (j['status'] ?? '').toString().toUpperCase();
      return s == 'COMPLETED' || s == 'DISPATCHED';
    }).length;

    final runningCount = activeOnlyJobs.where((j) => (j['status'] ?? '').toString().toUpperCase() == 'RUNNING').length;
    final testingCount = activeOnlyJobs.where((j) => (j['status'] ?? '').toString().toUpperCase() == 'TESTING').length;

    final filtered = _myAllJobs.where((j) {
      final status = (j['status'] ?? '').toString().toUpperCase();
      final jobNo = (j['job_no'] ?? '').toString().toLowerCase();
      final client = (j['client'] ?? '').toString().toLowerCase();
      final panel = (j['panel_type'] ?? '').toString().toLowerCase();

      bool matchesFilter = true;
      if (_activeFilter == 'RUNNING') {
        matchesFilter = (status == 'RUNNING');
      } else if (_activeFilter == 'TESTING') {
        matchesFilter = (status == 'TESTING');
      } else if (_activeFilter == 'DONE') {
        matchesFilter = (status == 'COMPLETED' || status == 'DISPATCHED');
      }

      bool matchesSearch = _searchQuery.isEmpty ||
          jobNo.contains(_searchQuery) ||
          client.contains(_searchQuery) ||
          panel.contains(_searchQuery);

      return matchesFilter && matchesSearch;
    }).toList();

    return RefreshIndicator(
      color: const Color(0xFFE88226),
      backgroundColor: const Color(0xFF0C2232),
      onRefresh: _loadWorkerSession,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          GestureDetector(
            onTap: () => setState(() => _currentTabIndex = 3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C2232),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF193B54)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.engineering_rounded, color: Color(0xFF38BDF8), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _workerFullName.toLowerCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE88226).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFE88226).withOpacity(0.6)),
                              ),
                              child: Text(
                                _ratingTag.toUpperCase(),
                                style: const TextStyle(color: Color(0xFFE88226), fontSize: 8.5, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          "★ ${_myRating.toStringAsFixed(1)} • Score: $_score100/100",
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildMetricTile("Assigned", "$assignedCount", "Total Panels", const Color(0xFF38BDF8), Icons.assignment_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile("In-Progress", "$inProgressCount", "Floor Active", const Color(0xFFE88226), Icons.timelapse_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile("Completed", "$completedCount", "QC Pass", const Color(0xFF10B981), Icons.check_circle_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0C2030),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF193B54)),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                icon: const Icon(Icons.search_rounded, size: 17, color: Color(0xFF0284C7)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 15, color: Colors.grey),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                hintText: "Search by Job #, Client, or Panel type...",
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 10),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterChip("ALL", "All Production ($assignedCount)"),
                const SizedBox(width: 6),
                _buildFilterChip("RUNNING", "Running ($runningCount)"),
                const SizedBox(width: 6),
                _buildFilterChip("TESTING", "Testing ($testingCount)"),
                const SizedBox(width: 6),
                _buildFilterChip("DONE", "Done ($completedCount)"),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text("No active production jobs assigned on floor yet.", style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5)),
              ),
            )
          else
            ...filtered.map((job) {
              final jobNo = (job['job_no'] ?? '-').toString();
              final client = (job['client'] ?? '-').toString();
              final panelType = (job['panel_type'] ?? '').toString().replaceAll('[PANEL]', '').replaceAll(RegExp(r'\[ITEM:.*?\]'), '').trim();
              final stage = (job['stage'] ?? 'Fabrication & Layout Stage').toString();
              final status = (job['status'] ?? '').toString().toUpperCase();
              final targetDateStr = (job['target_date'] ?? '-').toString();
              final double progress = (job['progress'] as num?)?.toDouble() ?? 0.25;
              final specsStr = (job['specs_detail'] ?? '').toString();
              final assignedWorker = (job['assigned_to'] ?? '').toString().toUpperCase();

              final bool isReassignedAway = (assignedWorker != _currentWorker);
              String transferTo = assignedWorker;
              String transferReason = "Reassigned by Director";
              final transferMatch = RegExp(r'\[TRANSFER:FROM:.*?\|TO:(.*?)\|REASON:(.*?)\|').firstMatch(specsStr);
              if (transferMatch != null) {
                transferTo = transferMatch.group(1) ?? assignedWorker;
                transferReason = transferMatch.group(2) ?? transferReason;
              }

              final bool isDone = (status == 'COMPLETED' || status == 'DISPATCHED');
              final Color statusClr = isDone ? const Color(0xFF10B981) : (status == 'TESTING' ? const Color(0xFFEA580C) : const Color(0xFF0284C7));

              return Stack(
                children: [
                  Opacity(
                    opacity: isReassignedAway ? 0.40 : 1.0,
                    child: GestureDetector(
                      onTap: isReassignedAway ? null : () => _showJobDetailsBottomSheet(job),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C2232),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isReassignedAway ? const Color(0xFFEF4444).withOpacity(0.5) : const Color(0xFF193B54),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0284C7).withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                                      ),
                                      child: Text(jobNo, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.w900)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(client, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: statusClr.withOpacity(0.18), borderRadius: BorderRadius.circular(4), border: Border.all(color: statusClr)),
                                  child: Text(status, style: TextStyle(color: statusClr, fontSize: 9.5, fontWeight: FontWeight.w900)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (panelType.isNotEmpty)
                              Text(panelType, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(stage, style: const TextStyle(color: Color(0xFF67B0D8), fontSize: 10.5, fontWeight: FontWeight.w600)),
                                Text("${(progress * 100).toInt()}% Done", style: TextStyle(color: statusClr, fontSize: 10.5, fontWeight: FontWeight.w900)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                minHeight: 3.5,
                                backgroundColor: const Color(0xFF132A3E),
                                valueColor: AlwaysStoppedAnimation<Color>(statusClr),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Divider(color: Color(0xFF16344C), height: 1),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.flag_rounded, size: 12, color: Color(0xFFE88226)),
                                    const SizedBox(width: 4),
                                    Text("Target: $targetDateStr", style: const TextStyle(color: Color(0xFFE88226), fontSize: 10.5, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                const Text("Tap for scope ➔", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isReassignedAway) ...[
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CustomPaint(painter: CrossLinePainter()),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF450A0A).withOpacity(0.96),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444), width: 1.3),
                        ),
                        child: Text("REASSIGNED TO: $transferTo • $transferReason", style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                  ],
                ],
              );
            }).toList(),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: 100-MARK FACTORY SCORECARD (MONTHLY / YEARLY ARCHIVE & 7-POINT FARAK)
  // =========================================================================
  Widget _build100MarkScorecardTab() {
    final now = DateTime.now();

    int activeScore = 0;
    double activeRating = 0.0;
    String activeTag = "NOT EVALUATED";
    String activeComment = "";

    int wM = 0, dM = 0, aM = 0, fM = 0, pM = 0, mM = 0, sM = 0;

    int prevScore = 0;
    Map<String, int> prevParams = {'Wiring': 0, 'Dressing': 0, 'Attendance': 0, 'Ferrule': 0, 'PLC': 0, 'Mounting': 0, 'Safety': 0};
    bool hasPreviousAudit = false;

    if (_isScoreYearlyMode) {
      final yearAudits = _myAuditHistoryList.where((a) => (a['audit_year'] as num?)?.toInt() == _scoreSelYear).toList();
      if (yearAudits.isNotEmpty) {
        final total = yearAudits.map((a) => (a['score_100'] as num?)?.toInt() ?? 0).reduce((a, b) => a + b);
        activeScore = (total / yearAudits.length).round();
        activeRating = (activeScore / 20.0).clamp(1.0, 5.0);
        activeTag = activeScore >= 90 ? "MASTER BUILDER" : (activeScore >= 80 ? "FACTORY STANDARD" : "AVERAGE FACTORY OUTPUT");
        activeComment = "Yearly cumulative average across ${yearAudits.length} audited month(s).";

        for (var a in yearAudits) {
          final m = _extractBreakdownMap((a['qc_breakdown'] ?? '').toString());
          wM += m['Wiring'] ?? 0;
          dM += m['Dressing'] ?? 0;
          aM += m['Attendance'] ?? 0;
          fM += m['Ferrule'] ?? 0;
          pM += m['PLC'] ?? 0;
          mM += m['Mounting'] ?? 0;
          sM += m['Safety'] ?? 0;
        }
        wM = (wM / yearAudits.length).round();
        dM = (dM / yearAudits.length).round();
        aM = (aM / yearAudits.length).round();
        fM = (fM / yearAudits.length).round();
        pM = (pM / yearAudits.length).round();
        mM = (mM / yearAudits.length).round();
        sM = (sM / yearAudits.length).round();
      } else {
        activeScore = 0;
        activeRating = 0.0;
        activeTag = "NOT EVALUATED (0)";
        activeComment = "No audits recorded for year $_scoreSelYear.";
      }
    } else {
      final monthRecord = _myAuditHistoryList.firstWhere(
        (a) =>
            (a['audit_month'] as num?)?.toInt() == _scoreSelMonth &&
            (a['audit_year'] as num?)?.toInt() == _scoreSelYear,
        orElse: () => {},
      );

      if (monthRecord.isNotEmpty) {
        activeScore = (monthRecord['score_100'] as num?)?.toInt() ?? 0;
        activeRating = (monthRecord['rating'] as num?)?.toDouble() ?? (activeScore / 20.0);
        activeTag = (monthRecord['rating_tag'] ?? 'FACTORY STANDARD').toString();
        activeComment = (monthRecord['rating_comment'] ?? 'Quality review recorded.').toString();

        final m = _extractBreakdownMap((monthRecord['qc_breakdown'] ?? '').toString());
        wM = m['Wiring'] ?? 0;
        dM = m['Dressing'] ?? 0;
        aM = m['Attendance'] ?? 0;
        fM = m['Ferrule'] ?? 0;
        pM = m['PLC'] ?? 0;
        mM = m['Mounting'] ?? 0;
        sM = m['Safety'] ?? 0;
      } else {
        final bool isCurrentMonth = (_scoreSelMonth == now.month && _scoreSelYear == now.year);
        if (isCurrentMonth && _score100 > 0) {
          activeScore = _score100;
          activeRating = _myRating;
          activeTag = _ratingTag;
          activeComment = _ratingComment;
          wM = _wiringMarks;
          dM = _dressingMarks;
          aM = _attendanceMarks;
          fM = _ferruleMarks;
          pM = _plcSignalMarks;
          mM = _mountingMarks;
          sM = _safetyQcMarks;
        } else {
          activeScore = 0;
          activeRating = 0.0;
          activeTag = "NOT EVALUATED (0/100)";
          activeComment = "No inspection audit recorded for ${_monthName(_scoreSelMonth)} $_scoreSelYear.";
        }
      }

      int prevM = _scoreSelMonth == 1 ? 12 : _scoreSelMonth - 1;
      int prevY = _scoreSelMonth == 1 ? _scoreSelYear - 1 : _scoreSelYear;

      final prevRecord = _myAuditHistoryList.firstWhere(
        (a) =>
            (a['audit_month'] as num?)?.toInt() == prevM &&
            (a['audit_year'] as num?)?.toInt() == prevY,
        orElse: () => {},
      );

      if (prevRecord.isNotEmpty) {
        hasPreviousAudit = true;
        prevScore = (prevRecord['score_100'] as num?)?.toInt() ?? 0;
        prevParams = _extractBreakdownMap((prevRecord['qc_breakdown'] ?? '').toString());
      }
    }

    final int scoreDiff = activeScore - prevScore;
    final List<String> gains = [];
    final List<String> losses = [];

    if (hasPreviousAudit && !_isScoreYearlyMode && activeScore > 0) {
      void checkFarak(String title, int current, int prev) {
        int diff = current - prev;
        if (diff > 0) {
          gains.add("$title (+$diff)");
        } else if (diff < 0) {
          losses.add("$title ($diff)");
        }
      }

      checkFarak('Wiring', wM, prevParams['Wiring'] ?? 0);
      checkFarak('Dressing', dM, prevParams['Dressing'] ?? 0);
      checkFarak('Attendance', aM, prevParams['Attendance'] ?? 0);
      checkFarak('Ferrule', fM, prevParams['Ferrule'] ?? 0);
      checkFarak('PLC', pM, prevParams['PLC'] ?? 0);
      checkFarak('Mounting', mM, prevParams['Mounting'] ?? 0);
      checkFarak('Safety', sM, prevParams['Safety'] ?? 0);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. DATE NAVIGATOR
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0C2232),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF193B54)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isScoreYearlyMode = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: !_isScoreYearlyMode ? const Color(0xFF0284C7) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Monthly Audit",
                          style: TextStyle(
                            color: !_isScoreYearlyMode ? Colors.white : const Color(0xFF94A3B8),
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isScoreYearlyMode = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _isScoreYearlyMode ? const Color(0xFF0284C7) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Yearly Overview",
                          style: TextStyle(
                            color: _isScoreYearlyMode ? Colors.white : const Color(0xFF94A3B8),
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Color(0xFF38BDF8)),
                    onPressed: () {
                      setState(() {
                        if (_isScoreYearlyMode) {
                          _scoreSelYear--;
                        } else {
                          if (_scoreSelMonth == 1) {
                            _scoreSelMonth = 12;
                            _scoreSelYear--;
                          } else {
                            _scoreSelMonth--;
                          }
                        }
                      });
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF071824),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(_isScoreYearlyMode ? Icons.calendar_today_rounded : Icons.calendar_month_rounded, size: 14, color: const Color(0xFFE88226)),
                        const SizedBox(width: 6),
                        Text(
                          _isScoreYearlyMode ? "Full Year $_scoreSelYear" : "${_monthName(_scoreSelMonth)} $_scoreSelYear",
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Color(0xFF38BDF8)),
                    onPressed: () {
                      setState(() {
                        if (_isScoreYearlyMode) {
                          _scoreSelYear++;
                        } else {
                          if (_scoreSelMonth == 12) {
                            _scoreSelMonth = 1;
                            _scoreSelYear++;
                          } else {
                            _scoreSelMonth++;
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. MAIN AUDIT SCORECARD BANNER
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0C2232),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5), width: 1.4),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Factory Quality Audit", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        _isScoreYearlyMode ? "Year $_scoreSelYear Archive" : "${_monthName(_scoreSelMonth)} $_scoreSelYear Audit",
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Text("$activeScore / 100", style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text("Standing Grade: $activeTag", style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text("${activeRating.toStringAsFixed(1)} ★", style: const TextStyle(color: Color(0xFFE88226), fontSize: 13, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF071420), borderRadius: BorderRadius.circular(8)),
                child: Text("\"$activeComment\"", style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5, fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),

        // 3. 🔍 7-POINT FARAK CARD
        if (hasPreviousAudit && !_isScoreYearlyMode && activeScore > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0C2232),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scoreDiff > 0
                    ? const Color(0xFF10B981).withOpacity(0.6)
                    : (scoreDiff < 0 ? const Color(0xFFEF4444).withOpacity(0.6) : const Color(0xFF0284C7).withOpacity(0.6)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "7-Parameter Farak vs ${_monthName(_scoreSelMonth == 1 ? 12 : _scoreSelMonth - 1)}:",
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (scoreDiff > 0 ? const Color(0xFF10B981) : (scoreDiff < 0 ? const Color(0xFFEF4444) : Colors.grey)).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        scoreDiff > 0 ? "+$scoreDiff pts ▲" : (scoreDiff < 0 ? "$scoreDiff pts ▼" : "0 pts (Same)"),
                        style: TextStyle(
                          color: scoreDiff > 0 ? const Color(0xFF10B981) : (scoreDiff < 0 ? const Color(0xFFEF4444) : Colors.white70),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (gains.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("🟢 Points Gained: ", style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold)),
                        Expanded(child: Text(gains.join(', '), style: const TextStyle(color: Colors.white, fontSize: 10.5))),
                      ],
                    ),
                  ),
                if (losses.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("🔴 Points Deducted: ", style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold)),
                      Expanded(child: Text(losses.join(', '), style: const TextStyle(color: Colors.white, fontSize: 10.5))),
                    ],
                  ),
                if (gains.isEmpty && losses.isEmpty)
                  const Text("Sabhi 7 parameters pichhle mahine ke barabar hain.", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        Text(
          _isScoreYearlyMode
              ? "Yearly Average Parameters (100 Marks):"
              : "${_monthName(_scoreSelMonth)} Parameters Breakdown (100 Marks):",
          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),

        // 4. 7 PARAMETERS PROGRESS BARS
        _buildParameterCard("1. Wiring & Crimping Quality", "Lug tightness, torque, wire gauge rating", wM, 20),
        _buildParameterCard("2. Wiring Dressing & Aesthetics", "Duct trunking, door loop wrap, tie spacing", dM, 20),
        _buildParameterCard("3. Attendance & Floor Punctuality", "Shift timing, daily punctuality, shop floor presence", aM, 20),
        _buildParameterCard("4. Ferrule & Tagging Match", "Schematic DWG cross-ferruling, TB numbering", fM, 10),
        _buildParameterCard("5. PLC & Signal Noise Isolation", "24VDC/Analog AC separation, shield wire earthing", pM, 10),
        _buildParameterCard("6. Component Mounting Alignment", "DIN rail alignment, heavy item sturdiness", mM, 10),
        _buildParameterCard("7. Safety & QC Factory Check", "Body earthing bonding, Megger insulation, HV", sM, 10),
      ],
    );
  }

  Widget _buildParameterCard(String title, String desc, int marks, int max) {
    final double ratio = max > 0 ? (marks / max).clamp(0.0, 1.0) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C2232),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF193B54)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Text("$marks / $max", style: const TextStyle(color: Color(0xFF10B981), fontSize: 12.5, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 2),
          Text(desc, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: const Color(0xFF132A3E),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 2: HISTORY (DELIVERED PANELS)
  // =========================================================================
  Widget _buildHistoryTab() {
    final completedPanels = _myAllJobs.where((j) {
      final s = (j['status'] ?? '').toString().toUpperCase();
      return s == 'COMPLETED' || s == 'DISPATCHED';
    }).toList();

    final filteredHistory = completedPanels.where((job) {
      final jNo = (job['job_no'] ?? '').toString().toLowerCase();
      final cName = (job['client'] ?? '').toString().toLowerCase();
      final pDesc = (job['panel_type'] ?? '').toString().toLowerCase();

      bool matchesSearch = _historySearchQuery.isEmpty ||
          jNo.contains(_historySearchQuery) ||
          cName.contains(_historySearchQuery) ||
          pDesc.contains(_historySearchQuery);

      final dateStr = (job['target_date'] ?? job['start_date'] ?? '').toString().toLowerCase();
      final specsStr = (job['specs_detail'] ?? '').toString();

      bool matchesPeriod = dateStr.contains(_historySelYear.toString());
      if (!_isHistoryYearlyMode) {
        final monthStr = _monthName(_historySelMonth).toLowerCase();
        if (!dateStr.contains(monthStr) && !specsStr.contains('PERIOD:$_historySelMonth-$_historySelYear')) {
          matchesPeriod = false;
        }
      }

      return matchesSearch && matchesPeriod;
    }).toList();

    return RefreshIndicator(
      color: const Color(0xFFE88226),
      backgroundColor: const Color(0xFF0C2232),
      onRefresh: _loadWorkerSession,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0C2232),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF193B54)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isHistoryYearlyMode = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: !_isHistoryYearlyMode ? const Color(0xFF0284C7) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            "Monthly Delivered",
                            style: TextStyle(
                              color: !_isHistoryYearlyMode ? Colors.white : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isHistoryYearlyMode = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _isHistoryYearlyMode ? const Color(0xFF0284C7) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            "Yearly Archive",
                            style: TextStyle(
                              color: _isHistoryYearlyMode ? Colors.white : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Color(0xFF38BDF8)),
                      onPressed: () {
                        setState(() {
                          if (_isHistoryYearlyMode) {
                            _historySelYear--;
                          } else {
                            if (_historySelMonth == 1) {
                              _historySelMonth = 12;
                              _historySelYear--;
                            } else {
                              _historySelMonth--;
                            }
                          }
                        });
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF071824),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(_isHistoryYearlyMode ? Icons.calendar_today_rounded : Icons.calendar_month_rounded, size: 14, color: const Color(0xFFE88226)),
                          const SizedBox(width: 6),
                          Text(
                            _isHistoryYearlyMode ? "Full Year $_historySelYear" : "${_monthName(_historySelMonth)} $_historySelYear",
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Color(0xFF38BDF8)),
                      onPressed: () {
                        setState(() {
                          if (_isHistoryYearlyMode) {
                            _historySelYear++;
                          } else {
                            if (_historySelMonth == 12) {
                              _historySelMonth = 1;
                              _historySelYear++;
                            } else {
                              _historySelMonth++;
                            }
                          }
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0C2232),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF193B54)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F2638), Color(0xFF081824)],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${filteredHistory.length}", style: const TextStyle(color: Color(0xFF10B981), fontSize: 20, fontWeight: FontWeight.w900)),
                      Text(
                        _isHistoryYearlyMode ? "Panels Built in $_historySelYear" : "Built in ${_monthName(_historySelMonth)}",
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 28, color: const Color(0xFF193B54)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("$_score100/100", style: const TextStyle(color: Color(0xFFE88226), fontSize: 18, fontWeight: FontWeight.w900)),
                      const Text("Active Rating", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0C2030),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF193B54)),
            ),
            child: TextField(
              controller: _historySearchCtrl,
              onChanged: (v) => setState(() => _historySearchQuery = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                icon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF0284C7)),
                suffixIcon: _historySearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14, color: Colors.grey),
                        onPressed: () {
                          _historySearchCtrl.clear();
                          setState(() => _historySearchQuery = '');
                        },
                      )
                    : null,
                hintText: "Search panels by Job #, Client...",
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (filteredHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 50),
              child: Center(
                child: Text(
                  "No panels recorded for ${_isHistoryYearlyMode ? '$_historySelYear' : '${_monthName(_historySelMonth)} $_historySelYear'}",
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ),
            )
          else
            ...filteredHistory.map((job) {
              final jobNo = (job['job_no'] ?? '-').toString();
              final client = (job['client'] ?? '-').toString();
              final panel = (job['panel_type'] ?? '').toString().replaceAll('[PANEL]', '').replaceAll(RegExp(r'\[ITEM:.*?\]'), '').trim();
              final targetDate = (job['target_date'] ?? '-').toString();
              final startDate = (job['start_date'] ?? '-').toString();
              final status = (job['status'] ?? 'COMPLETED').toString().toUpperCase();
              final timeAgo = _calculateTimeAgo(targetDate != '-' ? targetDate : startDate);

              final comparison = _compareScoreWithPrevious(job, completedPanels);
              final int diff = comparison['diff'] ?? 0;
              final int curScore = comparison['curScore'] ?? 0;
              final String summary = comparison['summary'] ?? '';

              return GestureDetector(
                onTap: () => _showHistoryInspectionModal(job, comparison),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C2232),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF0284C7).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                child: Text(jobNo, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.w900)),
                              ),
                              const SizedBox(width: 8),
                              Text(client, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF10B981)),
                            ),
                            child: Text(status, style: const TextStyle(color: Color(0xFF10B981), fontSize: 9.5, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(panel, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE88226).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFFE88226).withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.history_rounded, size: 12, color: Color(0xFFE88226)),
                                const SizedBox(width: 4),
                                Text(timeAgo, style: const TextStyle(color: Color(0xFFE88226), fontSize: 10, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          if (curScore > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: (diff > 0 ? const Color(0xFF10B981) : (diff < 0 ? const Color(0xFFEF4444) : Colors.grey)).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: (diff > 0 ? const Color(0xFF10B981) : (diff < 0 ? const Color(0xFFEF4444) : Colors.grey)).withOpacity(0.6),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    diff > 0 ? "+$diff pts ▲" : (diff < 0 ? "$diff pts ▼" : "0 pts (Same)"),
                                    style: TextStyle(
                                      color: diff > 0 ? const Color(0xFF10B981) : (diff < 0 ? const Color(0xFFEF4444) : Colors.white70),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF071420),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                diff > 0 ? Icons.trending_up_rounded : (diff < 0 ? Icons.trending_down_rounded : Icons.info_outline_rounded),
                                size: 13,
                                color: diff > 0 ? const Color(0xFF10B981) : (diff < 0 ? const Color(0xFFEF4444) : const Color(0xFF38BDF8)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  summary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9.8, fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),
                      const Divider(color: Color(0xFF16344C), height: 1),
                      const SizedBox(height: 6),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Delivered: $targetDate", style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                          const Text("View Full Analysis ➔", style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 3: WORKER PROFILE
  // =========================================================================
  Widget _buildProfileTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0C2232),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF193B54)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF0284C7).withOpacity(0.2),
                    child: const Icon(Icons.engineering_rounded, color: Color(0xFF38BDF8), size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_workerFullName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                        Text("Builder ID: $_currentWorker", style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold)),
                        Text("Phone: $_workerPhone", style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF193B54)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Factory Quality Standing:", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  Text(
                    "$_score100/100 • $_ratingTag",
                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildProfileTile(Icons.verified_user_rounded, "System Role", "Panel Fabrication & Control Wiring Specialist"),
        _buildProfileTile(Icons.factory_rounded, "Plant Location", "NextGen Controls - Rabale RTC 35 Operations Floor"),
        _buildProfileTile(Icons.workspace_premium_rounded, "Certified Grade", "$_ratingTag (${_myRating.toStringAsFixed(1)} ★)"),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFEF4444)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
            label: const Text("Sign Out / Switch Builder", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
            onPressed: _handleSignOut,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTile(IconData icon, String title, String val) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF0C2030),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF193B54)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF38BDF8), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                const SizedBox(height: 2),
                Text(
                  val,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String title, String count, String sub, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C2232),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF193B54)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.bold)),
              Icon(icon, color: color, size: 14),
            ],
          ),
          const SizedBox(height: 4),
          Text(count, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w900)),
          Text(sub, style: const TextStyle(color: Color(0xFF64748B), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final bool isSelected = _activeFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE88226) : const Color(0xFF0F2638),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? const Color(0xFFE88226) : const Color(0xFF1E4362)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class CrossLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEF4444).withOpacity(0.55)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(const Offset(4, 4), Offset(size.width - 4, size.height - 4), paint);
    canvas.drawLine(Offset(4, size.height - 4), Offset(size.width - 4, 4), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}