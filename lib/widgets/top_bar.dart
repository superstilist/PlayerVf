import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/page_state.dart';

class TopBar extends StatelessWidget {
  final VoidCallback onSettingsPressed;

  const TopBar({super.key, required this.onSettingsPressed});

  @override
  Widget build(BuildContext context) {
    final pageState = Provider.of<PageState>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Colors.black,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Music Player',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: onSettingsPressed,
                tooltip: 'Settings',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => pageState.setPage(PageType.home),
                style: TextButton.styleFrom(
                  foregroundColor: pageState.currentPage == PageType.home 
                    ? Colors.white 
                    : Colors.grey,
                ),
                child: const Text('Home'),
              ),
              TextButton(
                onPressed: () => pageState.setPage(PageType.favorite),
                style: TextButton.styleFrom(
                  foregroundColor: pageState.currentPage == PageType.favorite 
                    ? Colors.white 
                    : Colors.grey,
                ),
                child: const Text('Favorites'),
              ),
              TextButton(
                onPressed: () => pageState.setPage(PageType.playlist),
                style: TextButton.styleFrom(
                  foregroundColor: pageState.currentPage == PageType.playlist 
                    ? Colors.white 
                    : Colors.grey,
                ),
                child: const Text('Playlist'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}