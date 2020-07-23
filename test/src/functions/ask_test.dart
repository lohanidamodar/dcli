import 'package:dshell/dshell.dart';
import 'package:test/test.dart';

void main() {
  test('defaultValue', () {
    Settings().setVerbose(enabled: false);
    var result = ask(prompt: 'How old are you', defaultValue: '5');
    print('result: $result');
    result = ask(
        prompt: 'How old are you', defaultValue: '5', validator: Ask.integer);
    print('result: $result');
  }, skip: false);
}