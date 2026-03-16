import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/measurement_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const PqAnalyseApp());
}

class PqAnalyseApp extends StatelessWidget {
  const PqAnalyseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MeasurementProvider(),
      child: MaterialApp(
        title: 'PQ Analyse — A-Eberle PQBox',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
