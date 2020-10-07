import 'dart:io';

import '../../dcli.dart';

/// Utility methods to aid the dcli_completion app.
///

List<String> completionExpandScripts(String word, {String workingDirectory = '.'}) {
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
      var parts = split(word);

      searchTerm = parts.last;

      if (parts.length > 1) {
        root = join(root, parts.sublist(0, parts.length - 1).join(Platform.pathSeparator));
      }
    }
  }

  // /// if the work ends in a slash then we treat it as a directory
  // /// then we need to use the directory as the root so we
  // /// search in it.
  // if (exists(join(root, searchTerm))) {
  //   root = join(root, searchTerm);
  //   searchTerm = '';
  // }

  var entries = find('$searchTerm*', types: [Find.directory, Find.file], root: root, recursive: false).toList();

  var results = <String>[];
  for (var script in entries) {
    if (word.isEmpty || relative(script, from: workingDirectory).startsWith(word)) {
      var matchPath = join(root, script);
      if (isDirectory(matchPath)) {
        // its a directory add trailing slash and returning.
        results.add('${relative('$script', from: workingDirectory)}/');
      } else {
        results.add(relative(script, from: workingDirectory));
      }
    }
  }

  return results;
}
