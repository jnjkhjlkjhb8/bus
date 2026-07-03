import 'package:flutter/material.dart';

class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    this.controller,
    this.hintText = '搜尋',
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.leading,
  });
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => SearchBar(
    controller: controller,
    hintText: hintText,
    onChanged: onChanged,
    onTap: onTap,
    readOnly: readOnly,
    autoFocus: autofocus,
    leading: leading ?? const Icon(Icons.search_rounded),
    elevation: const WidgetStatePropertyAll(0),
  );
}
