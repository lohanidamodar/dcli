import 'dart:io';
import 'package:path/path.dart';

import '../../dshell.dart';
import '../functions/env.dart';
import '../functions/is.dart';
import '../functions/read.dart';

import '../pubspec/pubspec.dart';
import '../pubspec/pubspec_file.dart';
import '../pubspec/pubspec_manager.dart';

import '../settings.dart';

import '../util/ansi_color.dart';
import '../util/truepath.dart';
import '../util/with_lock.dart';

import 'commands/install.dart';

import 'pub_get.dart';
import 'script.dart';

/// Creates project directory structure
/// All projects live under the dshell cache
/// directory are form a virtual copy of the
/// user's Script with the additional files
/// required by dart.
class VirtualProject {
  /// the name of the project directory
  static const String projectDir = '.project';

  /// If this file exists in the VirtualProject directory
  /// then the project is using a local pubspec.yaml
  /// and we don't need to build the virtual project.
  static const _usingLocalPubpsecFilename = '.using.local.pubspec';
  static const _usingVirtualPubspecFilename = '.using.virtual.pubspec';
  static const _buildCompleteFilename = '.build.complete';

  /// The script this [VirtualProject] is for.
  final Script script;

  String _virtualProjectPath;

  // The absolute path to the scripts lib directory.
  // The script may not have a lib in which
  // case this directory wont' exist.
  String _scriptLibPath;

  String _projectLibPath;

  // A path to the 'Link' file in the project directory
  // that links to the actual script file.
  String _projectScriptLinkPath;

  String _projectPubspecPath;

  String _localPubspecIndicatorPath;

  String _virtualPubspecIndicatorPath;

  /// The absolute path to the projects lib directory.
  /// If the script lib exists then this will
  /// be a link to that directory.
  /// If the script lib doesn't exist then
  /// on will be created under the virtual project directory.
  String get projectCacheLib => _projectLibPath;

  /// The  absolute path to the
  /// virtual project's project directory.
  /// This is this is essentially:
  /// join(Settings().dshellCache, dirname(script), PROJECT_DIR)
  ///
  // String get path => _virtualProjectPath;

  /// The path to the virtual projects pubspec.yaml
  /// e.g. PROJECT_DIR/pubspec.yaml
  String get projectPubspecPath => _projectPubspecPath;

  // String _projectPubSpecPath;

  // String _runtimeLibPath;

  // String _runtimeScriptPath;

  String _runtimePubspecPath;
  String _runtimeProjectPath;

  bool _isProjectInitialised = false;

  /// The location of the pubspec.yaml file that will
  /// be used when running the project.
  ///
  /// See: runtimePath for how this is determined.
  String get runtimePubSpecPath => _runtimePubspecPath;

  /// The directory the project will be run from.
  /// For a project with an actual pubspec.yaml this
  /// will be the directory the pubspec.yaml file lives
  /// in (the same directory as the script). For
  /// a project that requires a virtual pubspec.yaml
  /// this will be in the projects cache directory
  /// located under ~/.dshell/cache....
  ///
  String get runtimeProjectPath => _runtimeProjectPath;

  /// The path to the script where we will run the script from.
  /// For script with an actual pubspec.yaml this will
  /// be the scripts natural directory. For a script
  /// with a virtual pubsec this will be the linked script
  /// in the projectc directory.
  String get runtimeScriptPath => join(_runtimeProjectPath, script.scriptname);

  NamedLock _lock;

  /// Creates a virtual project's directory
  /// and calls initialiseProject.
  /// The create does NOT build the project (i.e. call pub get)
  static VirtualProject create(Script script) {
    var dshellCachePath = Settings().dshellCachePath;
    var project = VirtualProject._internal(dshellCachePath, script);

    if (project.usingLocalPubspec) {
      // we don't need a virtual project as the script
      // is a full project in its own right.
      // why do we have two lib paths?
      _setLocalPaths(project, script);
      project._usingLocalPubspec = true;
    } else {
      // we need a virtual pubspec.
      // project._runtimeLibPath = project._projectLibPath;

      // project._runtimeScriptPath = project._projectScriptLinkPath;

      _setVirtualPaths(project);
      project._usingLocalPubspec = false;
    }
    Settings().verbose('Pubspec path: ${project._runtimePubspecPath}');
    Settings().verbose('Project path: ${project._runtimeProjectPath}');

    project.initialiseProject();
    return project;
  }

  /// loads an existing virtual project.
  static VirtualProject load(Script script) {
    var dshellCachePath = Settings().dshellCachePath;
    var project = VirtualProject._internal(dshellCachePath, script);

    if (project.usingLocalPubspec) {
      // why do we have two lib paths?
      _setLocalPaths(project, script);
    } else {
      _setVirtualPaths(project);
    }

    Settings().verbose('Pubspec path: ${project._runtimePubspecPath}');
    Settings().verbose('Project path: ${project._runtimeProjectPath}');

    return project;
  }

  static void _setProjectPaths(VirtualProject project, Script script) {
    project._projectLibPath = join(project._virtualProjectPath, 'lib');

    project._scriptLibPath = join(script.path, 'lib');
    project._projectScriptLinkPath =
        join(project._virtualProjectPath, script.scriptname);
    project._projectPubspecPath =
        join(project._virtualProjectPath, 'pubspec.yaml');
  }

  static void _setVirtualPaths(VirtualProject project) {
    _setProjectPaths(project, project.script);

    project._runtimePubspecPath = project._projectPubspecPath;
    project._runtimeProjectPath = project._virtualProjectPath;
  }

  static void _setLocalPaths(VirtualProject project, Script script) {
    // project._runtimeLibPath = join(script.path, 'lib');

    // project._runtimeScriptPath = script.path;
    _setProjectPaths(project, script);

    project._runtimePubspecPath = join(dirname(script.path), 'pubspec.yaml');

    project._runtimeProjectPath = dirname(script.path);
  }

  bool _usingLocalPubspec;

  /// true if we are using a local pubspec (e.g. its in the same dir as the script.)
  bool get usingLocalPubspec {
    _usingLocalPubspec ??=
        script.hasPubSpecYaml() && !script.hasPubspecAnnotation;
    return _usingLocalPubspec;
  }

  VirtualProject._internal(String cacheRootPath, this.script) {
    // /home/bsutton/.dshell/cache/home/bsutton/git/dshell/test/test_scripts/hello_world.project
    _virtualProjectPath = join(cacheRootPath,
        Script.sansRoot(script.scriptDirectory), script.basename + projectDir);

    _localPubspecIndicatorPath =
        join(_virtualProjectPath, _usingLocalPubpsecFilename);
    _virtualPubspecIndicatorPath =
        join(_virtualProjectPath, _usingVirtualPubspecFilename);

    _isProjectInitialised = exists(_virtualProjectPath) &&
        (exists(_localPubspecIndicatorPath) ||
            exists(_virtualPubspecIndicatorPath));

    _lock = NamedLock(
      name: 'virtual_project.lock',
      lockPath: dirname(_virtualProjectPath),
    );
  }

  /// Creates the projects cache directory under the
  ///  root directory of our global cache directory - [cacheRootDir]
  ///
  /// The projec cache directory contains
  /// Link to script file
  /// Link to 'lib' directory of script file
  ///  or
  /// Lib directory if the script file doesn't have a lib dir.
  /// pubsec.yaml copy from script annotationf
  ///  or
  /// Link to scripts own pubspec.yaml file.
  /// hashes.yaml file.
  void initialiseProject() {
    _lock.withLock(() {
      if (!exists(_virtualProjectPath)) {
        createDir(_virtualProjectPath, recursive: true);
        print('Created Virtual Project at $_virtualProjectPath');
      }

      if (usingLocalPubspec) {
        // create the indicator file so when we load
        // the virtual project we know its a local
        // pubspec without having to parse the script
        // for a pubspec annotation.
        if (exists(_virtualPubspecIndicatorPath)) {
          delete(_virtualPubspecIndicatorPath);
        }
        touch(_localPubspecIndicatorPath, create: true);

        // clean up any old files.
        // as the script may have changed from virtual to local.
        if (exists(_projectScriptLinkPath)) {
          delete(_projectScriptLinkPath);
        }

        if (exists(_projectLibPath)) {
          delete(_projectLibPath);
        }

        if (exists(_projectPubspecPath)) {
          delete(_projectPubspecPath);
        }
      } else {
        if (exists(_localPubspecIndicatorPath)) {
          delete(_localPubspecIndicatorPath);
        }
        touch(_virtualPubspecIndicatorPath, create: true);

        // create the files/links for a virtual pubspec.
        _createScriptLink(script);
        _createLib();
        PubSpecManager(this).createVirtualPubSpec();
      }
      _isProjectInitialised = true;
    });
  }

  /// We need to create a link to the script
  /// from the project cache.
  void _createScriptLink(Script script) {
    if (!exists(_projectScriptLinkPath, followLinks: false)) {
      var link = Link(_projectScriptLinkPath);
      link.createSync(script.path);
    }
  }

  ///
  /// Builds the project.
  /// This essentially means that we run pub get
  /// however if the project hasn't been initialised
  /// then we initialise the project as well.
  /// if [background] is set to true then we
  /// run the build as a background process.
  /// [background] defaults to [false]
  ///
  void build({bool background = false}) {
    /// Check that dshells install has been rum.
    if (!exists(Settings().dshellCachePath)) {
      printerr(red(
          "The dshell cache doesn't exists. Please run 'dshell install' and then try again."));
      printerr('');
      printerr('');
      throw InstallException('DShell needs to be re-installed');
    }

    _lock.withLock(() {
      try {
        if (!isInitialised) {
          initialiseProject();
        }
        if (background) {
          // we run the clean in the background
          // by running another copy of dshell.
          print('DShell clean started in the background.');
          // ('dshell clean ${script.path}' | 'echo > ${dirname(path)}/log').run;
          // 'dshell -v clean ${script.path}'.run;
          '${DShellPaths().dshellName} -v=${join(Directory.systemTemp.path, 'dshell.clean.log')} clean ${script.path}'
              .start(detached: true, runInShell: true);
        } else {
          print('Running pub get...');
          _pubget();
          _markBuildComplete();
        }
      } on PubGetException {
        print(red("\ndshell clean failed due to the 'pub get' call failing."));
      }
    }, waiting: 'Waiting for clean to complete...');
  }

  /// Causes a pub get to be run against the project.
  ///
  /// The projects cache must already exist and be
  /// in a consistent state.
  ///
  /// This is normally done when the project cache is first
  /// created and when a script's pubspec changes.
  void _pubget() {
    _lock.withLock(() {
      var pubGet = PubGet(this);
      pubGet.run(compileExecutables: false);
    });
  }

  // Create the cache lib as a real file or a link
  // as needed.
  // This may change on each run so need to able
  // to swap between a link and a dir.
  void _createLib() {
    // does the script have a lib directory
    if (exists(_scriptLibPath)) {
      // does the cache have a lib
      if (exists(projectCacheLib)) {
        // ensure we have a link from cache to the scriptlib
        if (!FileSystemEntity.isLinkSync(projectCacheLib)) {
          // its not a link so we need to recreate it as a link
          // the script directory structure may have changed since
          // the last run.
          deleteDir(projectCacheLib);
          symlink(_scriptLibPath, projectCacheLib);
        }
      } else {
        symlink(_scriptLibPath, projectCacheLib);
      }
    } else {
      // no script lib so we need to create a real lib
      // directory in the project cache.
      if (!exists(projectCacheLib)) {
        // create the lib as it doesn't exist.
        createDir(projectCacheLib);
      } else {
        if (FileSystemEntity.isLinkSync(projectCacheLib)) {
          {
            // delete the link and create the required directory
            delete(projectCacheLib);
            createDir(projectCacheLib);
          }
        }
        // it exists and is the correct type so no action required.
      }
    }

    // does the project cache lib link exist?
  }

  /// used by the 'doctor' command to prints the details for this project.
  void get doctor {
    print('');
    print('');
    print('Script Details');
    _colprint('Name', script.scriptname);
    _colprint('Directory', privatePath(script.scriptDirectory));
    _colprint('Virtual Project', privatePath(_virtualProjectPath));
    print('');

    print('');
    print('Virtual pubspec.yaml');
    read(_projectPubspecPath).forEach((line) {
      print('  ${_makeSafe(line)}');
    });

    print('');
    _colprint('Dependencies', '');
    pubSpec().dependencies.forEach((d) => _colprint(d.name, '${d.rehydrate()}'));
  }

  String _makeSafe(String line) {
    return line.replaceAll(HOME, '<HOME>');
  }

  void _colprint(String label, String value, {int pad = 25}) {
    print('${label.padRight(pad)}: $value');
  }

  ///
  /// reads and returns the project's virtual pubspec
  /// and returns it.
  PubSpec pubSpec() {
    return PubSpecFile.fromFile(_runtimePubspecPath);
  }

  /// Called after a project is created
  /// and pub get run to mark a project as runnable.
  void _markBuildComplete() {
    /// Create a file indicating that the clean has completed.
    /// This file is used by the RunCommand to know if the project
    /// is in a runnable state.

    touch(join(_virtualProjectPath, _buildCompleteFilename), create: true);
  }

  /// Returns true if the projects structure has
  /// been intialised. An initialised project
  /// is one where the virtual project directory has been created
  /// a pubspec.yaml exists any required links have been created.
  ///
  /// See: isRunnable to see if a project is in a runnable state.
  bool get isInitialised => _isProjectInitialised;

  /// Returns [true] if the project has been intialised
  /// and a [build] has been run (which essentially calls
  /// pub get).
  bool get isRunnable {
    return _isProjectInitialised &&
        exists(join(_virtualProjectPath, _buildCompleteFilename));
  }
}
