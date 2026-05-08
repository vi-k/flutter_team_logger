import 'package:flutter/material.dart';
import 'package:flutter_team_logger/flutter_team_logger.dart';

import 'logging.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _showLogs() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Logs(theme: theme, logStorage: logStorage),
      ),
    );
  }

  // Future<void> _showLogsOld() async {
  //   await Navigator.push(
  //     context,
  //     MaterialPageRoute<void>(
  //       builder: (_) => LogsOld(theme: theme, logStorage: logStorage),
  //     ),
  //   );
  // }

  // Future<void> _showLogs2() async {
  //   await Navigator.push(
  //     context,
  //     MaterialPageRoute<void>(
  //       builder: (_) => Logs2(theme: theme, logStorage: logStorage),
  //     ),
  //   );
  // }

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
              // ElevatedButton(
              //   onPressed: _showLogsOld,
              //   child: StreamBuilder<void>(
              //     stream: logStorage.onChanged,
              //     builder: (_, __) => Text('Logs old (${logStorage.count})'),
              //   ),
              // ),
              // ElevatedButton(
              //   onPressed: _showLogs2,
              //   child: StreamBuilder<void>(
              //     stream: logStorage.onChanged,
              //     builder: (_, __) => Text('Logs old 2 (${logStorage.count})'),
              //   ),
              // ),
            ],
          ),
        ),
      );
}
