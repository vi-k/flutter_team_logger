// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_team_logger/flutter_team_logger.dart';

import 'logging.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _log = log.copyWith(name: 'logs');

  Future<void> _showLogs() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Logs(
          theme: uiTheme,
          logStorage: logStorage,
          onPaused: () => _log.w('[b]paused[/b]'),
          onResumed: () => _log.w('[b]resumed[/b]'),
          onCleared: () => _log.w('[b]cleared[/b]'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('Logs demo'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 16,
            children: [
              ElevatedButton(
                onPressed: _showLogs,
                child: StreamBuilder<void>(
                  stream: logStorage.onChanged,
                  builder: (_, __) => Text('Logs (${logStorage.count})'),
                ),
              ),
            ],
          ),
        ),
      );
}
