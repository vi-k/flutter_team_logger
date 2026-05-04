import 'package:example/logging.dart';
import 'package:flutter/material.dart';

import 'package:flutter_team_logger/flutter_team_logger.dart';

class App extends StatelessWidget {
  const App({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Logs',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: Logs(
          theme: theme,
          logStorage: logStorage,
        ),
      );
}
