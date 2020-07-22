@Timeout(Duration(seconds: 600))
import 'dart:io';

import 'package:dshell/dshell.dart';
import 'package:dshell/src/functions/env.dart';
import 'package:dshell/src/script/script.dart';
import 'package:dshell/src/script/virtual_project.dart';
import 'package:dshell/src/util/dshell_paths.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

/// TestPaths sets up an isolated area for unit tests to run without
/// interfering with your normal dshell install.
///
/// To do this it modifies the folling environment variables:
///
/// HOME = /tmp/dshell/home
/// PUB_CACHE = /tmp/dshell/.pub_cache
///
/// The dshell cache is therefore located at:
///
/// /tmp/dshell/cache
///
/// As the unit test suite creates an isolated .pub-cache it will be empty.
/// As such when the unit tests start dshell is not actually installed in the
/// active .pub-cache.
///
///
/// The result is that dshell is neither available in .pub-cache nor installed into
/// .dshell.
///
/// This is not a problem for running most unit tests as the are using the
/// primary .pub-cache. It is however a problem if you attempt to spawn
/// a dshell instance on the cli.
///
/// The first time TestPaths is called it will create the necessary paths
/// and install dshell.
///
/// To ensure that the install happens at the start of each test run (and then only once)
/// we store the test runs PID into /tmp/dshell/PID.
/// If the PID changes we know we need to recreate and reinstall everything.
///
///

class TestPaths {
  static final TestPaths _self = TestPaths._internal();

  static String testRoot;

  String home;
  //String scriptDir;
  String testScriptPath;
  String scriptName;
  //String projectPath;
  String testRootForPid;

  factory TestPaths() {
    return _self;
  }

  TestPaths._internal() {
    testRoot = join(rootPath, 'tmp', 'dshell');
    // each unit test process has its own directory.

    testRootForPid = join(testRoot, '$pid');

    print('unit test for $pid running from $pid');

    // redirecct HOME to /tmp/dshell/home
    var home = truepath(testRoot, 'home');
    setEnv('HOME', home);

    // // create test .pub-cache dir
    // var pubCachePath = truepath(TEST_ROOT, PubCache().cacheDir);
    // setEnv('PUB_CACHE', pubCachePath);

    // add the unit test dshell/bin path to the front
    // of the PATH so that our test version of dshell tooling
    // will run when we spawn a dshell process.
    var path = PATH;
    path.insert(0, Settings().dshellBinPath);

    // .pub-cache so we run the test version of dshell.
    // path.insert(0, pubCachePath);

    setEnv('PATH', path.join(Env().pathDelimiter));

    var dshellPath = Settings().dshellPath;
    if (!dshellPath.startsWith(join(rootPath, 'tmp')) ||
        !HOME.startsWith(join(rootPath, 'tmp')))
    //  ||        !env('PUB_CACHE').startsWith('/tmp'))
    {
      printerr(
          '''Something went wrong, the dshell path or HOME for unit tests is NOT pointing to /tmp. 
          dshell's path is pointing at $dshellPath
          HOME is pointing at $HOME
          PUB_CACHE is pointing at ${env('PUB_CACHE')}
          ''');
      printerr('We have shutdown the unit tests to protect your filesystem.');
      exit(1);
    }

    // create test home dir
    recreateDir(home);

    recreateDir(Settings().dshellPath);

    recreateDir(Settings().dshellBinPath);

    // the cache is normally in .dshellPath
    // but just in case its not we create it directly
    recreateDir(Settings().dshellCachePath);

    // recreateDir(pubCachePath);

    testScriptPath = truepath(testRoot, 'scripts');

    installDshell();
  }

  String projectPath(String scriptName) {
    String projectPath;
    var projectScriptPath =
        join(dirname(scriptName), basenameWithoutExtension(scriptName));
    if (scriptName.startsWith(Platform.pathSeparator)) {
      projectPath = truepath(Settings().dshellCachePath,
          Script.sansRoot(projectScriptPath) + VirtualProject.projectDir);
    } else {
      projectPath = truepath(
          Settings().dshellCachePath,
          Script.sansRoot(testScriptPath),
          projectScriptPath + VirtualProject.projectDir);
    }
    return projectPath;
  }

  void recreateDir(String path) {
    // if (exists(path)) {
    //   deleteDir(path, recursive: true);
    // }
    if (!exists(path)) {
      createDir(path, recursive: true);
    }
  }

  void installDshell() {
    'pub global activate --source path .'.run;

    which('dshell').forEach(print);

    print('dshell path: ${Settings().dshellPath}');

    if (!exists(Settings().dshellPath)) {
      createDir(Settings().dshellPath);

      '${DShellPaths().dshellName} install'.run;
    }
  }
}