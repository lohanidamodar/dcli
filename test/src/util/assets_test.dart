import 'package:dcli/dcli.dart' hide equals;
import 'package:test/test.dart';

void main() {
  test('Assets().toString', () async {
    const path = 'assets/templates/basic.dart';
    final content = Assets().loadString(path);

    expect(content, isNotNull);

    var actual =
        read(join(Script.current.pathToProjectRoot, 'lib', 'src', path))
            .toList()
            .join('\n');

    /// the join trims the last \n
    actual += '\n';

    expect(content, equals(actual));
  });

  test('Assets().list', () async {
    const path = 'assets/templates/';
    final templates = Assets().list('*', root: path);

    final base = join(Script.current.pathToProjectRoot, 'lib', 'src', path);

    expect(
      templates,
      unorderedEquals(
        <String>[
          join(base, 'basic.dart'),
          join(base, 'hello_world.dart'),
          join(base, 'README.md'),
          join(base, 'analysis_options.yaml'),
          join(base, 'pubspec.yaml.template'),
          join(base, 'cmd_args.dart')
        ],
      ),
    );
  });
}
