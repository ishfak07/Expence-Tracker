import 'dart:convert';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Entry point of the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SriLankaExpenseTrackerApp());
}

/// User model for authentication
class User {
  final String username;
  final String password;
  final String displayName;

  User({
    required this.username,
    required this.password,
    required this.displayName,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'displayName': displayName,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        username: json['username'],
        password: json['password'],
        displayName: json['displayName'],
      );
}

/// Simple enum to control the time filter on the dashboard.
enum TimeFilter { today, week, month, all }

/// Data model for a single expense.
///
/// Kept intentionally simple for beginners:
///  - [title]: short description like "Lunch" or "Bus to Colombo".
///  - [note]: optional longer text.
class Expense {
  final String id;
  final String title;
  final String? note;
  final double amount;
  final DateTime date;
  final String category;

  Expense({
    required this.id,
    required this.title,
    this.note,
    required this.amount,
    required this.date,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'amount': amount,
        'date': date.toIso8601String(),
        'category': category,
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'],
        title: json['title'],
        note: json['note'],
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date']),
        category: json['category'],
      );
}

/// Root widget that holds **all app state** (theme, settings, expenses).
class SriLankaExpenseTrackerApp extends StatefulWidget {
  const SriLankaExpenseTrackerApp({super.key});

  @override
  State<SriLankaExpenseTrackerApp> createState() =>
      _SriLankaExpenseTrackerAppState();
}

class _SriLankaExpenseTrackerAppState extends State<SriLankaExpenseTrackerApp> {
  final _uuid = const Uuid();
  final List<String> _categories = const [
    'Food',
    'Travel',
    'Bills',
    'Mobile Reload',
    'Other'
  ];

  // --- User Authentication ---
  User? _currentUser;
  bool _isLoggedIn = false;

  List<Expense> _expenses = [];

  // --- Settings / preferences ---
  bool _onboardingDone = false;
  ThemeMode _themeMode = ThemeMode.light;
  String _currencySymbol = 'Rs.'; // or "LKR"
  double? _monthlyBudget; // null = no budget set
  String? _pinCode; // null or empty = no lock
  bool _isUnlocked = false;
  bool _dailyReminderEnabled = false; // placeholder switch (no plugin here)

  // Bottom navigation
  int _selectedTab = 0; // 0 = Home, 1 = History, 2 = Settings

  // Dashboard filter
  TimeFilter _timeFilter = TimeFilter.today;

  // History screen
  DateTime? _selectedHistoryMonth; // first day of month

  SharedPreferences? _prefs;

  // Normalize usernames to avoid case/whitespace login issues
  String _normalizeUsername(String username) => username.trim().toLowerCase();

  NumberFormat get _currencyFormat => NumberFormat.currency(
        locale: 'en_LK',
        symbol: '$_currencySymbol ',
        decimalDigits: 2,
      );

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  // Get user-specific key prefix (normalized username)
  String _userKey(String key) {
    final u = _currentUser?.username;
    final normalized = u == null ? 'guest' : _normalizeUsername(u);
    return '${normalized}_$key';
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    // Check if user is logged in
    final lastUser = prefs.getString('last_logged_in_user');
    if (lastUser != null) {
      final userData = prefs.getString('user_$lastUser');
      if (userData != null) {
        _currentUser = User.fromJson(jsonDecode(userData));
        _isLoggedIn = true;
        await _loadFromPrefs();
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadFromPrefs() async {
    if (_prefs == null || _currentUser == null) return;

    // Load expenses list (user-specific)
    final stored = _prefs!.getStringList(_userKey('expenses'));
    if (stored != null) {
      _expenses = stored
          .map((e) => Expense.fromJson(jsonDecode(e) as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    }

    // Basic settings (user-specific)
    _onboardingDone = _prefs!.getBool(_userKey('onboarding_done')) ?? false;
    final themeString = _prefs!.getString(_userKey('theme_mode')) ?? 'light';
    _themeMode = switch (themeString) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };
    _currencySymbol = _prefs!.getString(_userKey('currency_symbol')) ?? 'Rs.';
    _monthlyBudget = _prefs!.getDouble(_userKey('monthly_budget'));
    _pinCode = _prefs!.getString(_userKey('pin_code'));
    _dailyReminderEnabled =
        _prefs!.getBool(_userKey('daily_reminder')) ?? false;

    // If no PIN, app is already unlocked
    _isUnlocked = _pinCode == null || _pinCode!.isEmpty;

    // Default history month = latest month with data or current month
    _selectedHistoryMonth = _findLatestMonthWithData() ??
        DateTime(DateTime.now().year, DateTime.now().month);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveExpenses() async {
    if (_currentUser == null) return;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final list = _expenses.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_userKey('expenses'), list);
  }

  Future<void> _saveSettings() async {
    if (_currentUser == null) return;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(_userKey('onboarding_done'), _onboardingDone);
    await prefs.setString(
        _userKey('theme_mode'),
        switch (_themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          _ => 'system',
        });
    await prefs.setString(_userKey('currency_symbol'), _currencySymbol);
    if (_monthlyBudget != null) {
      await prefs.setDouble(_userKey('monthly_budget'), _monthlyBudget!);
    } else {
      await prefs.remove(_userKey('monthly_budget'));
    }
    if (_pinCode != null && _pinCode!.isNotEmpty) {
      await prefs.setString(_userKey('pin_code'), _pinCode!);
    } else {
      await prefs.remove(_userKey('pin_code'));
    }
    await prefs.setBool(_userKey('daily_reminder'), _dailyReminderEnabled);
  }

  // ---------- User Authentication helpers ----------

  Future<bool> _registerUser(
      String username, String password, String displayName) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();

    final normalized = _normalizeUsername(username);
    if (normalized.isEmpty || password.isEmpty || displayName.trim().isEmpty) {
      return false;
    }

    // Check if username already exists
    if (prefs.getString('user_$normalized') != null) {
      return false; // User already exists
    }

    // Create and save new user (store normalized username)
    final user = User(
      username: normalized,
      password: password,
      displayName: displayName.trim(),
    );
    await prefs.setString('user_$normalized', jsonEncode(user.toJson()));

    // Log in the new user
    setState(() {
      _currentUser = user;
      _isLoggedIn = true;
    });
    await prefs.setString('last_logged_in_user', normalized);
    await _loadFromPrefs();

    return true;
  }

  Future<bool> _loginUser(String username, String password) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();

    final normalized = _normalizeUsername(username);
    // Try normalized key first, then legacy key for backward compatibility
    String? userData = prefs.getString('user_$normalized');
    userData ??= prefs.getString('user_$username');
    if (userData == null) {
      return false; // User not found
    }

    final user = User.fromJson(jsonDecode(userData));
    if (user.password != password) {
      return false; // Wrong password
    }

    // Login successful
    setState(() {
      _currentUser = user;
      _isLoggedIn = true;
    });
    await prefs.setString('last_logged_in_user', user.username);
    await _loadFromPrefs();

    return true;
  }

  Future<void> _logoutUser() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    // Remove per-user keys for the current user
    if (_currentUser != null) {
      final keys = [
        _userKey('expenses'),
        _userKey('onboarding_done'),
        _userKey('theme_mode'),
        _userKey('currency_symbol'),
        _userKey('monthly_budget'),
        _userKey('pin_code'),
        _userKey('daily_reminder'),
      ];
      for (final k in keys) {
        await prefs.remove(k);
      }
    }

    await prefs.remove('last_logged_in_user');

    setState(() {
      _currentUser = null;
      _isLoggedIn = false;
      _expenses = [];
      _onboardingDone = false;
      _themeMode = ThemeMode.light;
      _currencySymbol = 'Rs.';
      _monthlyBudget = null;
      _pinCode = null;
      _isUnlocked = false;
      _dailyReminderEnabled = false;
      _selectedTab = 0;
      _timeFilter = TimeFilter.today;
    });
  }

  // ---------- Expense helpers ----------

  void _addExpense(String title, String? note, double amount, DateTime date,
      String category) {
    final expense = Expense(
      id: _uuid.v4(),
      title: title,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      amount: amount,
      date: date,
      category: category,
    );

    setState(() {
      _expenses.insert(0, expense);
      _expenses.sort((a, b) => b.date.compareTo(a.date));
    });
    _saveExpenses();
  }

  void _deleteExpenseWithUndo(BuildContext context, Expense expense) {
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index == -1) return;

    setState(() {
      _expenses.removeAt(index);
    });
    _saveExpenses();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Expense deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              _expenses.insert(index, expense);
            });
            _saveExpenses();
          },
        ),
      ),
    );
  }

  List<Expense> _filteredExpensesForDashboard() {
    final now = DateTime.now();
    return _expenses.where((e) {
      switch (_timeFilter) {
        case TimeFilter.today:
          return e.date.year == now.year &&
              e.date.month == now.month &&
              e.date.day == now.day;
        case TimeFilter.week:
          final startOfWeek =
              now.subtract(Duration(days: now.weekday - 1)); // Monday
          final endOfWeek = startOfWeek.add(const Duration(days: 7));
          return !e.date.isBefore(startOfWeek) && e.date.isBefore(endOfWeek);
        case TimeFilter.month:
          return e.date.year == now.year && e.date.month == now.month;
        case TimeFilter.all:
          return true;
      }
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  double _totalForExpenses(List<Expense> list) =>
      list.fold(0.0, (sum, e) => sum + e.amount);

  Map<String, double> _categorySummary(List<Expense> list) {
    final map = <String, double>{for (final c in _categories) c: 0};
    for (final e in list) {
      if (map.containsKey(e.category)) {
        map[e.category] = map[e.category]! + e.amount;
      }
    }
    return map;
  }

  DateTime? _findLatestMonthWithData() {
    if (_expenses.isEmpty) return null;
    final latest =
        _expenses.reduce((a, b) => a.date.isAfter(b.date) ? a : b).date;
    return DateTime(latest.year, latest.month);
  }

  List<DateTime> _allMonthsWithData() {
    final set = <String>{};
    for (final e in _expenses) {
      set.add('${e.date.year}-${e.date.month}');
    }
    final list = set.map((s) {
      final parts = s.split('-');
      return DateTime(int.parse(parts[0]), int.parse(parts[1]));
    }).toList()
      ..sort((a, b) => b.compareTo(a));
    return list;
  }

  // ---------- Backup / restore ----------

  void _backupToClipboard(BuildContext context) {
    final jsonString = jsonEncode(_expenses.map((e) => e.toJson()).toList());
    Clipboard.setData(ClipboardData(text: jsonString));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup copied to clipboard')),
    );
  }

  Future<void> _restoreFromJson(BuildContext context) async {
    final controller = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste backup JSON'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Paste JSON here'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Restore')),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      final decoded = jsonDecode(result) as List<dynamic>;
      final restored = decoded
          .map((e) => Expense.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _expenses = restored..sort((a, b) => b.date.compareTo(a.date));
      });
      await _saveExpenses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expenses restored from backup')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid backup format')),
        );
      }
    }
  }

  // ---------- PIN lock ----------

  void _setPin(String pin) {
    setState(() {
      _pinCode = pin;
      _isUnlocked = false;
    });
    _saveSettings();
  }

  void _removePin() {
    setState(() {
      _pinCode = null;
      _isUnlocked = true;
    });
    _saveSettings();
  }

  void _onUnlocked() {
    setState(() {
      _isUnlocked = true;
    });
  }

  // ---------- Build ----------

  ThemeData _buildLightTheme() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.poppins().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00C853),
        brightness: Brightness.light,
        surface: const Color(0xFFF5F7FB),
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: Colors.white,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: GoogleFonts.poppins().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00C853),
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF050814),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Iishi's Expense Tracker",
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // LEVEL 5: Show login screen if not logged in
    if (!_isLoggedIn) {
      return LoginScreen(
        onLogin: _loginUser,
        onRegister: _registerUser,
      );
    }

    // LEVEL 4: Onboarding first time
    if (!_onboardingDone) {
      return OnboardingScreen(
        onFinish: () {
          setState(() {
            _onboardingDone = true;
          });
          _saveSettings();
        },
      );
    }

    // LEVEL 3: PIN lock
    if (_pinCode != null && _pinCode!.isNotEmpty && !_isUnlocked) {
      return PinLockScreen(
        onUnlocked: _onUnlocked,
        correctPin: _pinCode!,
      );
    }

    // Main shell with bottom navigation
    final homeBody = IndexedStack(
      index: _selectedTab,
      children: [
        _buildDashboardTab(),
        _buildHistoryTab(),
        SettingsTab(
          themeMode: _themeMode,
          currencySymbol: _currencySymbol,
          monthlyBudget: _monthlyBudget,
          dailyReminderEnabled: _dailyReminderEnabled,
          hasPin: _pinCode != null && _pinCode!.isNotEmpty,
          onThemeChanged: (mode) {
            setState(() => _themeMode = mode);
            _saveSettings();
          },
          onCurrencyChanged: (symbol) {
            setState(() => _currencySymbol = symbol);
            _saveSettings();
          },
          onBudgetChanged: (value) {
            setState(() => _monthlyBudget = value);
            _saveSettings();
          },
          onClearAllData: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Clear all data?'),
                content:
                    const Text('This will delete all expenses and settings.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Clear')),
                ],
              ),
            );
            if (confirmed == true) {
              setState(() {
                _expenses = [];
                _monthlyBudget = null;
                _pinCode = null;
                _isUnlocked = true;
              });
              final prefs = _prefs ?? await SharedPreferences.getInstance();
              // Remove only current user's data, keep other accounts
              final keys = [
                _userKey('expenses'),
                _userKey('onboarding_done'),
                _userKey('theme_mode'),
                _userKey('currency_symbol'),
                _userKey('monthly_budget'),
                _userKey('pin_code'),
                _userKey('daily_reminder'),
              ];
              for (final k in keys) {
                await prefs.remove(k);
              }
              await _saveExpenses();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All data cleared')),
                );
              }
            }
          },
          onBackup: () => _backupToClipboard(context),
          onRestore: () => _restoreFromJson(context),
          onToggleReminder: (enabled) {
            setState(() => _dailyReminderEnabled = enabled);
            _saveSettings();
          },
          onSetPin: _setPin,
          onRemovePin: _removePin,
          onLogout: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Logout?'),
                content: const Text(
                    'You will need to login again to access your data.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Logout')),
                ],
              ),
            );
            if (confirmed == true) {
              await _logoutUser();
            }
          },
          currentUsername: _currentUser?.displayName,
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(child: homeBody),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
      floatingActionButton: _selectedTab == 0
          ? OpenContainer(
              transitionType: ContainerTransitionType.fadeThrough,
              closedElevation: 6,
              closedShape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(28)),
              ),
              closedColor: Theme.of(context).colorScheme.primary,
              openBuilder: (context, _) => AddExpenseScreen(
                categories: _categories,
                currencySymbol: _currencySymbol,
                onAddExpense: (title, note, amount, date, category) {
                  _addExpense(title, note, amount, date, category);
                },
              ),
              closedBuilder: (context, openContainer) => FloatingActionButton(
                onPressed: openContainer,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 32),
              ),
            )
          : null,
    );
  }

  // ---------- Dashboard tab (LEVEL 1 + 2 + part of 3) ----------

  Widget _buildDashboardTab() {
    final filtered = _filteredExpensesForDashboard();
    final total = _totalForExpenses(filtered);
    final categoryData = _categorySummary(filtered);

    final now = DateTime.now();
    final currentMonthTotal = _totalForExpenses(
      _expenses
          .where((e) => e.date.year == now.year && e.date.month == now.month)
          .toList(),
    );

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 260,
          floating: false,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF00C853),
                    Color(0xFF40C4FF),
                    Color(0xFF7C4DFF),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    // Logo at top left corner
                    Positioned(
                      top: 8,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: SizedBox(
                          height: 120,
                          width: 120,
                          child: Image.asset(
                            'logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    // Main content
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Iishi's",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Expense Tracker',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Total Spent (${_timeFilterLabel(_timeFilter)})',
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currencyFormat.format(total),
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMiniStat('Txns', '${filtered.length}'),
                            Container(
                                height: 20, width: 1, color: Colors.white24),
                            _buildMiniStat(
                              'Avg',
                              filtered.isEmpty
                                  ? '-'
                                  : _currencyFormat
                                      .format(total / filtered.length),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // LEVEL 3: Budget quick view
                        if (_monthlyBudget != null)
                          _buildBudgetChip(currentMonthTotal, _monthlyBudget!),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // LEVEL 1: Time filter segmented control
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<TimeFilter>(
              segments: const [
                ButtonSegment(value: TimeFilter.today, label: Text('Today')),
                ButtonSegment(value: TimeFilter.week, label: Text('This week')),
                ButtonSegment(
                    value: TimeFilter.month, label: Text('This month')),
                ButtonSegment(value: TimeFilter.all, label: Text('All')),
              ],
              selected: {_timeFilter},
              onSelectionChanged: (newSet) {
                setState(() {
                  _timeFilter = newSet.first;
                });
              },
            ),
          ),
        ),

        // LEVEL 2: Charts + category summary
        SliverToBoxAdapter(
          child: filtered.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 210,
                        child: Card(
                          elevation: 2,
                          shadowColor: Colors.black12,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Expanded(
                                    child: _buildPieChart(categoryData, total)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildBarChart(filtered)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'By category',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              ...categoryData.entries
                                  .where((e) => e.value > 0)
                                  .map(
                                    (entry) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2.0),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color:
                                                  _getCategoryColor(entry.key),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(entry.key)),
                                          Text(_currencyFormat
                                              .format(entry.value)),
                                        ],
                                      ),
                                    ),
                                  )
                                  ,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Recent transactions',
              style: TextStyle(
                  color: Colors.grey[600], fontWeight: FontWeight.w600),
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.only(bottom: 80),
          sliver: filtered.isEmpty
              ? SliverToBoxAdapter(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Icon(Icons.receipt_long_rounded,
                          size: 72, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No expenses yet',
                        style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap + to add your first expense',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final expense = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Dismissible(
                          key: ValueKey(expense.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            decoration: BoxDecoration(
                              color: Colors.red[100],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: Icon(Icons.delete_outline,
                                color: Colors.red[700]),
                          ),
                          onDismissed: (_) =>
                              _deleteExpenseWithUndo(context, expense),
                          child: _buildExpenseTile(expense),
                        ),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildBudgetChip(double usedThisMonth, double budget) {
    final remaining = budget - usedThisMonth;
    final ratio = (usedThisMonth / budget).clamp(0.0, 1.5);
    final isOver = remaining < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            'Budget: ${_currencyFormat.format(budget)}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: ratio > 1 ? 1 : ratio,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(
                isOver ? Colors.redAccent : Colors.lightGreenAccent),
          ),
          const SizedBox(height: 4),
          Text(
            isOver
                ? 'Over by ${_currencyFormat.format(remaining.abs())}'
                : 'Remaining: ${_currencyFormat.format(remaining)}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _timeFilterLabel(TimeFilter filter) {
    return switch (filter) {
      TimeFilter.today => 'Today',
      TimeFilter.week => 'This week',
      TimeFilter.month => 'This month',
      TimeFilter.all => 'All time',
    };
  }

  Widget _buildPieChart(Map<String, double> categoryData, double total) {
    if (total <= 0) {
      return const Center(child: Text('No data'));
    }
    return PieChart(
      PieChartData(
        sectionsSpace: 0,
        centerSpaceRadius: 30,
        sections: categoryData.entries.where((e) => e.value > 0).map((entry) {
          final percentage = (entry.value / total) * 100;
          return PieChartSectionData(
            color: _getCategoryColor(entry.key),
            value: entry.value,
            title: percentage > 8 ? '${percentage.toStringAsFixed(0)}%' : '',
            radius: 40,
            titleStyle: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBarChart(List<Expense> expenses) {
    if (expenses.isEmpty) {
      return const Center(child: Text('No data'));
    }

    // Group by day
    final map = <DateTime, double>{};
    for (final e in expenses) {
      final key = DateTime(e.date.year, e.date.month, e.date.day);
      map[key] = (map[key] ?? 0) + e.amount;
    }
    final days = map.keys.toList()..sort();

    return BarChart(
      BarChartData(
        barGroups: [
          for (int i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: map[days[i]]!,
                  color: const Color(0xFF00BFA5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= days.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    DateFormat.d().format(days[index]),
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildExpenseTile(Expense expense) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _getCategoryColor(expense.category).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getCategoryIcon(expense.category),
            color: _getCategoryColor(expense.category),
            size: 24,
          ),
        ),
        title: Text(
          expense.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${expense.category} • ${DateFormat.MMMd().format(expense.date)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            if (expense.note != null && expense.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  expense.note!,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        trailing: Text(
          _currencyFormat.format(expense.amount),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food':
        return Colors.orangeAccent;
      case 'Travel':
        return Colors.blueAccent;
      case 'Bills':
        return Colors.redAccent;
      case 'Mobile Reload':
        return Colors.purpleAccent;
      case 'Other':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant_menu_rounded;
      case 'Travel':
        return Icons.directions_bus_filled_rounded;
      case 'Bills':
        return Icons.receipt_rounded;
      case 'Mobile Reload':
        return Icons.smartphone_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }

  // ---------- History tab (LEVEL 2: monthly history) ----------

  Widget _buildHistoryTab() {
    final months = _allMonthsWithData();
    final selectedMonth = _selectedHistoryMonth;
    final now = DateTime.now();
    final effectiveMonth = selectedMonth ??
        (months.isNotEmpty ? months.first : DateTime(now.year, now.month));

    final monthExpenses = _expenses
        .where((e) =>
            e.date.year == effectiveMonth.year &&
            e.date.month == effectiveMonth.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final total = _totalForExpenses(monthExpenses);
    final avg = monthExpenses.isEmpty ? 0.0 : total / monthExpenses.length;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Monthly history',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              DropdownButton<DateTime>(
                value: effectiveMonth,
                items: (months.isEmpty ? [effectiveMonth] : months)
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(DateFormat.yMMM().format(m)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedHistoryMonth = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total spent'),
                      const SizedBox(height: 4),
                      Text(
                        _currencyFormat.format(total),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Average / txn'),
                      const SizedBox(height: 4),
                      Text(
                        monthExpenses.isEmpty
                            ? '-'
                            : _currencyFormat.format(avg),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: monthExpenses.isEmpty
                ? Center(
                    child: Text(
                      'No expenses recorded for ${DateFormat.yMMM().format(effectiveMonth)}',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    itemCount: monthExpenses.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: _buildExpenseTile(monthExpenses[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------- Add Expense Screen (LEVEL 2: notes, modern form) ----------

class AddExpenseScreen extends StatefulWidget {
  final List<String> categories;
  final String currencySymbol;
  final void Function(String title, String? note, double amount, DateTime date,
      String category) onAddExpense;

  const AddExpenseScreen({
    super.key,
    required this.categories,
    required this.currencySymbol,
    required this.onAddExpense,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _selectedCategory = 'Food';

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (_titleController.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount and title')),
      );
      return;
    }

    widget.onAddExpense(
      _titleController.text.trim(),
      _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      amount,
      _selectedDate,
      _selectedCategory,
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Iishi's Expense Tracker"),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How much?',
                        style: GoogleFonts.poppins(color: Colors.grey[500])),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.poppins(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00BFA5),
                      ),
                      decoration: InputDecoration(
                        prefixText: '${widget.currencySymbol} ',
                        border: InputBorder.none,
                        hintText: '0.00',
                      ),
                    ),
                    const Divider(height: 40),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                        labelText: 'Title (e.g. Lunch, Bus Ticket)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: const Icon(Icons.notes_rounded),
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Category',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700])),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: widget.categories.map((cat) {
                        final isSelected = _selectedCategory == cat;
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          selectedColor: const Color(0xFF00BFA5),
                          labelStyle: TextStyle(
                              color:
                                  isSelected ? Colors.white : Colors.black87),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedCategory = cat);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                size: 20, color: Colors.grey),
                            const SizedBox(width: 12),
                            Text(DateFormat.yMMMd().format(_selectedDate)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BFA5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  child: Text(
                    'Save expense',
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ---------- PIN Lock Screen (LEVEL 3) ----------

class PinLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final String correctPin;

  const PinLockScreen(
      {super.key, required this.onUnlocked, required this.correctPin});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final _controller = TextEditingController();
  String? _error;

  void _submit() {
    if (_controller.text == widget.correctPin) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'Incorrect PIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 64),
              const SizedBox(height: 16),
              const Text('Enter PIN to unlock'),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                maxLength: 4,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: InputDecoration(
                  counterText: '',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _submit, child: const Text('Unlock')),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Onboarding Screens (LEVEL 4) ----------

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  void _next() {
    if (_page < 2) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onFinish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _OnboardingPage(
                    icon: Icons.track_changes_rounded,
                    title: 'Track your daily expenses',
                    subtitle:
                        'Quickly record cash spending in Sri Lankan Rupees.',
                  ),
                  _OnboardingPage(
                    icon: Icons.bar_chart_rounded,
                    title: 'See where money goes',
                    subtitle:
                        'Smart charts and category breakdowns help you save.',
                  ),
                  _OnboardingPage(
                    icon: Icons.lock_rounded,
                    title: 'Offline & private',
                    subtitle:
                        'Data stays on your device with optional PIN lock.',
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  width: _page == i ? 16 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        _page == i ? const Color(0xFF00BFA5) : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(_page == 2 ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96, color: const Color(0xFF00BFA5)),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ---------- Settings Screen (LEVEL 3 + 4) ----------

class SettingsTab extends StatelessWidget {
  final ThemeMode themeMode;
  final String currencySymbol;
  final double? monthlyBudget;
  final bool dailyReminderEnabled;
  final bool hasPin;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<double?> onBudgetChanged;
  final VoidCallback onClearAllData;
  final VoidCallback onBackup;
  final VoidCallback onRestore;
  final ValueChanged<bool> onToggleReminder;
  final ValueChanged<String> onSetPin;
  final VoidCallback onRemovePin;
  final VoidCallback onLogout;
  final String? currentUsername;

  const SettingsTab({
    super.key,
    required this.themeMode,
    required this.currencySymbol,
    required this.monthlyBudget,
    required this.dailyReminderEnabled,
    required this.hasPin,
    required this.onThemeChanged,
    required this.onCurrencyChanged,
    required this.onBudgetChanged,
    required this.onClearAllData,
    required this.onBackup,
    required this.onRestore,
    required this.onToggleReminder,
    required this.onSetPin,
    required this.onRemovePin,
    required this.onLogout,
    this.currentUsername,
  });

  @override
  Widget build(BuildContext context) {
    final budgetController = TextEditingController(
      text: monthlyBudget != null ? monthlyBudget!.toStringAsFixed(0) : '',
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appearance',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: themeMode,
                  onChanged: (v) => onThemeChanged(v ?? ThemeMode.system),
                  title: const Text('Follow system'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: themeMode,
                  onChanged: (v) => onThemeChanged(v ?? ThemeMode.light),
                  title: const Text('Light mode'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: themeMode,
                  onChanged: (v) => onThemeChanged(v ?? ThemeMode.dark),
                  title: const Text('Dark mode'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Currency', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'Rs.',
                  groupValue: currencySymbol,
                  onChanged: (v) => onCurrencyChanged(v ?? 'Rs.'),
                  title: const Text('Rs.'),
                ),
                RadioListTile<String>(
                  value: 'LKR',
                  groupValue: currencySymbol,
                  onChanged: (v) => onCurrencyChanged(v ?? 'LKR'),
                  title: const Text('LKR'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Budget', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Monthly budget limit'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: budgetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      prefixText: 'Rs. ',
                      hintText: 'e.g. 50000',
                    ),
                    onSubmitted: (value) {
                      final v = double.tryParse(value);
                      onBudgetChanged(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        final v = double.tryParse(budgetController.text);
                        onBudgetChanged(v);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Security', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_rounded),
                  title: Text(hasPin ? 'Change PIN' : 'Set PIN'),
                  subtitle: const Text('Lock the app with a 4-digit PIN'),
                  onTap: () async {
                    final controller = TextEditingController();
                    final newPin = await showDialog<String?>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Set PIN'),
                        content: TextField(
                          controller: controller,
                          maxLength: 4,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          decoration: const InputDecoration(counterText: ''),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, controller.text),
                              child: const Text('Save')),
                        ],
                      ),
                    );
                    if (newPin != null && newPin.length == 4) {
                      onSetPin(newPin);
                    }
                  },
                ),
                if (hasPin)
                  ListTile(
                    leading: const Icon(Icons.lock_open_rounded),
                    title: const Text('Remove PIN'),
                    onTap: onRemovePin,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Data', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('Backup (copy JSON)'),
                  onTap: onBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.upload_rounded),
                  title: const Text('Restore from JSON'),
                  onTap: onRestore,
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded),
                  title: const Text('Clear all data'),
                  onTap: onClearAllData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Reminders (optional)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Daily reminder'),
              subtitle: const Text('Show a simple reminder inside the app'),
              value: dailyReminderEnabled,
              onChanged: onToggleReminder,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Account', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                if (currentUsername != null)
                  ListTile(
                    leading: const Icon(Icons.person_rounded),
                    title: const Text('Logged in as'),
                    subtitle: Text(currentUsername!),
                  ),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Logout'),
                  subtitle: const Text('Switch to a different account'),
                  onTap: onLogout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('About', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: SizedBox(
                height: 32,
                width: 32,
                child: Image.asset('logo.png', fit: BoxFit.contain),
              ),
              title: const Text("Iishi's Expense Tracker"),
              subtitle:
                  const Text('Offline, beginner-friendly Flutter finance app.'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Login/Register Screen
class LoginScreen extends StatefulWidget {
  final Future<bool> Function(String username, String password) onLogin;
  final Future<bool> Function(
      String username, String password, String displayName) onRegister;

  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoginMode = true;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submit() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Please fill all fields');
      return;
    }

    if (!_isLoginMode && _displayNameController.text.isEmpty) {
      _showError('Please enter your display name');
      return;
    }

    setState(() => _isLoading = true);

    bool success;
    if (_isLoginMode) {
      success = await widget.onLogin(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!success) {
        _showError('Invalid username or password');
      }
    } else {
      success = await widget.onRegister(
        _usernameController.text.trim(),
        _passwordController.text,
        _displayNameController.text.trim(),
      );
      if (!success) {
        _showError('Username already exists');
      }
    }

    setState(() => _isLoading = false);
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF00C853),
              Color(0xFF40C4FF),
              Color(0xFF7C4DFF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 80,
                        width: 80,
                        child: Image.asset('logo.png', fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Iishi's Expense Tracker",
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLoginMode
                            ? 'Login to your account'
                            : 'Create new account',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (!_isLoginMode)
                        TextField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                        ),
                      if (!_isLoginMode) const SizedBox(height: 16),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.account_circle_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_rounded),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _isLoginMode ? 'Login' : 'Register',
                                  style: const TextStyle(fontSize: 16),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLoginMode = !_isLoginMode;
                            _usernameController.clear();
                            _passwordController.clear();
                            _displayNameController.clear();
                          });
                        },
                        child: Text(
                          _isLoginMode
                              ? "Don't have an account? Register"
                              : 'Already have an account? Login',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }
}
