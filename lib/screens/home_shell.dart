import 'package:flutter/material.dart';
import 'screen_one.dart';
import 'screen_two.dart';
import 'screen_three.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DataAnalice',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          ScreenOne(),
          ScreenTwo(),
          ScreenThree(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF0D0D0D),
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune),
            label: 'Config',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.science),
            label: 'Data Lab',
          ),
        ],
      ),
    );
  }
}
