import 'dart:io';

import '../../dcli.dart';

/// Utility methods to aid the dcli_completion app.
///

List<String> completionExpandScripts(String word,
    {String workingDirectory = '.'}) {
  var root = workingDirectory;

  var searchTerm = word;

  // a trailing slash and we treat the word as a directory.
  if (word.endsWith(Platform.pathSeparator)) {
    root = join(root, word);
    searchTerm = '';
  } else {
    // no trailing slash but the word may contain a directory path
    // in which case we use the last part as the search term
    // and append any remaining path to the root.
    if (word.isNotEmpty) {
      final parts = split(word);

      searchTerm = parts.last;

      if (parts.length > 1) {
        root = join(root,
            parts.sublist(0, parts.length - 1).join(Platform.pathSeparator));
      }
    }
  }

  /// if the resulting path is invalid return an empty list.
  if (!exists(root)) return <String>[];

  // /// if the work ends in a slash then we treat it as a directory
  // /// then we need to use the directory as the root so we
  // /// search in it.
  // if (exists(join(root, searchTerm))) {
  //   root = join(root, searchTerm);
  //   searchTerm = '';
  // }

  final entries = find('$searchTerm*',
          types: [Find.directory, Find.file], root: root, recursive: false)
      .toList();

  final results = <String>[];
  for (final script in entries) {
    if (word.isEmpty ||
        relative(script, from: workingDirectory).startsWith(word)) {
      final matchPath = join(root, script);
      String filePath;
      if (isDirectory(matchPath)) {
        // its a directory add trailing slash and returning.
        filePath = '${relative(script, from: workingDirectory)}/';
      } else {
        filePath = relative(script, from: workingDirectory);
      }
      if (filePath.contains(' ')) {
        /// we quote filenames that include a space
        filePath = '"$filePath"';
      }
      results.add(filePath);
    }
  }

  return results;
}
