import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/page_state.dart';

class PageSwitchButton extends StatelessWidget {
  const PageSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final pageState = Provider.of<PageState>(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => pageState.setPage(PageType.home),
          color: pageState.currentPage == PageType.home ? Colors.blue : Colors.grey,
        ),
        IconButton(
          icon: const Icon(Icons.favorite),
          onPressed: () => pageState.setPage(PageType.favorite),
          color: pageState.currentPage == PageType.favorite ? Colors.blue : Colors.grey,
        ),
        IconButton(
          icon: const Icon(Icons.playlist_play),
          onPressed: () => pageState.setPage(PageType.playlist),
          color: pageState.currentPage == PageType.playlist ? Colors.blue : Colors.grey,
        ),
      ],
    );
  }
}