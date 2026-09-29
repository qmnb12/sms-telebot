import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../service.dart';
import '../state.dart';
import '../styles.dart';
import '../widgets/action_button.dart';

class PushedAppsPage extends StatefulWidget {
  const PushedAppsPage({super.key});

  @override
  State<PushedAppsPage> createState() => _PushedAppsPageState();
}

class _PushedAppsPageState extends State<PushedAppsPage> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, String>> _allApps = [];
  Set<String> _initialPackages = {};
  Set<String> _selectedPackages = {};

  bool _isLoading = true;
  bool _isInputChanged = false;
  bool? _saveResult;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final appState = context.read<AppState>();

    Set<String> savedPackages = {};
    if (appState.pushedAppsJson.isNotEmpty) {
      final decoded = safeDecode(appState.pushedAppsJson);
      if (decoded is List) savedPackages = decoded.map((p) => p.toString()).toSet();
    }

    final apps = await getInstalledAppsNative();
    if (!mounted) return;
    setState(() {
      _allApps = apps;
      _initialPackages = Set<String>.from(savedPackages);
      _selectedPackages = Set<String>.from(savedPackages);
      _isLoading = false;
    });
  }

  bool _areSetsEqual(Set<String> a, Set<String> b) {
    return a.length == b.length && a.containsAll(b);
  }

  void _onToggleApp(String packageName, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedPackages.add(packageName);
      } else {
        _selectedPackages.remove(packageName);
      }
      _isInputChanged = !_areSetsEqual(_initialPackages, _selectedPackages);
      _saveResult = null;
    });
  }

  Future<void> _saveApps() async {
    final list = _selectedPackages.toList()..sort();
    final jsonString = list.isEmpty ? '' : jsonEncode(list);

    await context.read<AppState>().updatePushedApps(jsonString);
    if (!mounted) return;
    setState(() {
      _initialPackages = Set<String>.from(_selectedPackages);
      _isInputChanged = false;
      _saveResult = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final filteredApps = (_searchQuery.isEmpty
      ? List<Map<String, String>>.from(_allApps)
      : _allApps.where((app) {
        final name = (app['name'] ?? '').toLowerCase();
        final pkg = (app['packageName'] ?? '').toLowerCase();
        return name.contains(_searchQuery) || pkg.contains(_searchQuery);
      }).toList())
      ..sort((a, b) {
        final aPkg = a['packageName'] ?? '';
        final bPkg = b['packageName'] ?? '';
        final aSelected = _initialPackages.contains(aPkg);
        final bSelected = _initialPackages.contains(bPkg);

        if (aSelected != bSelected) return aSelected ? -1 : 1;
        return (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pushed_apps),
        centerTitle: true,
        elevation: 2,
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: TextField(
                controller: _searchController,
                decoration: CustomStyle.compactInput(
                  labelText: l10n.pushed_search,
                  prefixIcon: const Icon(Icons.search, applyTextScaling: true),
                  suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear, applyTextScaling: true),
                      onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                    )
                    : null,
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value.trim().toLowerCase());
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.pushed_total(_allApps.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    l10n.pushed_selected(_selectedPackages.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold, color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filteredApps.isEmpty
                ? Center( child: Text(l10n.pushed_notFound))
                : ListView.separated(
                  itemCount: filteredApps.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final app = filteredApps[index];
                    final pkg = app['packageName'] ?? '';
                    final name = app['name'] ?? pkg;
                    final isSelected = _selectedPackages.contains(pkg);

                    return SwitchListTile(
                      key: ValueKey(pkg),
                      dense: true,
                      title: Text(
                        name, style: const TextStyle(fontSize: 16),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        pkg, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                      value: isSelected,
                      onChanged: (value) => _onToggleApp(pkg, value),
                    );
                  },
                ),
            ),
          ],
        ),
      bottomNavigationBar: SafeArea(
        child: ActionButton(
          label: l10n.action_save,
          onPressed: _isInputChanged ? _saveApps : null,
          isSuccess: _saveResult,
        ),
      ),
    );
  }
}
