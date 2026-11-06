import 'package:flutter/material.dart';

import '../services/vitals_service.dart';
import 'alerts_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.service});

  final VitalsService service;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              DashboardScreen(service: widget.service),
              HistoryScreen(service: widget.service),
              AlertsScreen(service: widget.service),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Início',
              ),
              const NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history_rounded),
                label: 'Histórico',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: widget.service.alerts.isNotEmpty,
                  label: Text('${widget.service.alerts.length}'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: widget.service.alerts.isNotEmpty,
                  label: Text('${widget.service.alerts.length}'),
                  child: const Icon(Icons.notifications_rounded),
                ),
                label: 'Alertas',
              ),
            ],
          ),
        );
      },
    );
  }
}
