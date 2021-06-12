#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Build.Construction;
using Microsoft.Build.Evaluation;
using Microsoft.Build.Execution;
using Microsoft.Build.Experimental.ProjectCache;
using Microsoft.Build.Framework;
using Microsoft.Build.Graph;
using Microsoft.Build.Logging;
using static RulesMSBuild.Tools.Builder.BazelLogger;

namespace RulesMSBuild.Tools.Builder
{
    public class Builder
    {
        private readonly BuildContext _context;
        private readonly string _action;
        private readonly BuildManager _buildManager;
        private readonly MsBuildCacheManager _cacheManager;
        private readonly BazelMsBuildLogger _msbuildLog;
        private readonly TargetGraph? _targetGraph;

        public Builder(BuildContext context)
        {
            _context = context;
            _action = _context.Command.Action.ToLower();
            _buildManager = BuildManager.DefaultBuildManager;
            var trimPath = _context.Bazel.ExecRoot + Path.DirectorySeparatorChar;
            if (_context.DiagnosticsEnabled)
            {
                _targetGraph = new TargetGraph(trimPath, _context.ProjectFile, null);
            }

            _cacheManager = new MsBuildCacheManager(_buildManager, _context.Bazel.ExecRoot, _targetGraph);

            var pathTrimmer = new PathReplacer(context.Bazel);
            _msbuildLog = new BazelMsBuildLogger(
                _context.DiagnosticsEnabled ? LoggerVerbosity.Normal : LoggerVerbosity.Quiet, 
                (m) => pathTrimmer.ReplacePath(m) 
                , _targetGraph!);
        }

        public int Build()
        {
            ProjectCollection? projectCollection = null;
            BuildResultCode? result = null;
            try
            {
                projectCollection = BeginBuild();

                result = ExecuteBuild(projectCollection);

                EndBuild(result!.Value);
            }
            finally
            {
                _buildManager.Dispose();
                projectCollection?.Dispose();
            }

            return (int) result;
        }

        private void EndBuild(BuildResultCode result)
        {
            if (_context.MSBuild.UseCaching && result == BuildResultCode.Success)
            {
                _cacheManager.AfterExecuteBuild();
            }

            _buildManager.EndBuild();
            
            if (_targetGraph != null)
            {
                File.WriteAllText(_context.LabelPath(".dot"), _targetGraph.ToDot());
            }
            
            if (result == BuildResultCode.Success)
            {
                if (_action == "restore")
                {
                    FixRestoreOutputs();
                }

                if (_action == "build" && _context.IsTest)
                {
                    // todo make this less hacky
                    var loggerPath = Path.Combine(
                        Path.GetDirectoryName(_context.NuGetConfig)!,
                        "packages/junitxml.testlogger/3.0.87/build/_common");
                    var tfmPath = Path.Combine(_context.MSBuild.OutputPath, _context.Tfm);
                    foreach (var dll in Directory.EnumerateFiles(loggerPath))
                    {
                        var filename = Path.GetFileName(dll);
                        File.Copy(dll, Path.Combine(tfmPath, filename));
                    }
                }

                if (_context.IsExecutable && _action == "build")
                {
                    var basename = _context.Bazel.Label.Name;
                    if (Path.DirectorySeparatorChar == '\\')
                    {
                        // there's not a great "IsWindows" method in c#
                        basename += ".exe";
                    }

                    File.WriteAllLines(_context.OutputPath(_context.Tfm, "runfiles.info"), new string[]
                    {
                        // first line is the expected location of the runfiles directory from the assembly location
                        $"../{basename}.runfiles",
                        // second line is the origin workspace (nice to have)
                        _context.Bazel.Label.Workspace,
                        // third is the package (nice to have)
                        _context.Bazel.Label.Package
                    });
                }
            }
        }

        private BuildResultCode ExecuteBuild(ProjectCollection projectCollection)
        {
            // don't load the project ahead of time, otherwise the evaluation won't be included in the binlog output
            var source = new TaskCompletionSource<BuildResultCode>();
            var flags = BuildRequestDataFlags.ProvideProjectStateAfterBuild;

            // our restore outputs are relative to the project directory
            Environment.CurrentDirectory = _context.ProjectDirectory;
            if (_context.MSBuild.GraphBuild)
            {
                var graphData = new GraphBuildRequestData(
                    new ProjectGraphEntryPoint(_context.ProjectFile, projectCollection.GlobalProperties),
                    _context.MSBuild.Targets,
                    null,
                    flags);
                var submission = _buildManager.PendBuildRequest(graphData);

                submission.ExecuteAsync(_ => source.SetResult((submission.BuildResult.OverallResult)), submission);
            }
            else
            {
                if (_action == "restore" && !Directory.Exists(_context.MSBuild.RestoreDir))
                {
                    Directory.CreateDirectory(_context.MSBuild.RestoreDir);
                }

                var remaining = _context.MSBuild.Requests.Length;
                var results = new BuildResultCode[_context.MSBuild.Requests.Length];
                for (var i = 0; i < _context.MSBuild.Requests.Length; i++)
                {
                    var buildRequest = _context.MSBuild.Requests[i];
                    // this is a *Build* Request, NOT a *Graph* build request
                    // build request only builds a single project in isolation, and any cache misses are considered errors.
                    // loading up the project graph to begin with enables some other optimizations.
                    var projectGlobalProperties = new Dictionary<string, string>(projectCollection.GlobalProperties);
                    foreach (var (key, value) in buildRequest.Properties)
                        projectGlobalProperties[key] = value;

                    var data = new BuildRequestData(
                        _context.ProjectFile,
                        projectGlobalProperties,
                        null,
                        buildRequest.Targets,
                        null,
                        // Keep the project items that we have discovered for publish so publish doesn't do a re-build.
                        flags
                    );
                    // var thisSource = new TaskCompletionSource<BuildResultCode>();
                    var i1 = i;
                    _buildManager.PendBuildRequest(data)
                        .ExecuteAsync(submission =>
                        {
                            lock (results)
                            {
                                results[i1] = submission.BuildResult.OverallResult;
                                if (!ValidateTfm(submission.BuildResult.ProjectStateAfterBuild))
                                    results[i1] = BuildResultCode.Failure;

                                remaining--;
                                if (remaining > 0) return;
                                var aggregateResult = BuildResultCode.Failure;
                                if (results.All(s => s == BuildResultCode.Success))
                                    aggregateResult = BuildResultCode.Success;

                                source.SetResult(aggregateResult);
                            }
                        }, new object());
                }
            }

            WriteBazelProps();

            var result = source.Task.GetAwaiter().GetResult();

            return result;
        }

        private bool ValidateTfm(ProjectInstance project)
        {
            var actualTfm = project.GetProperty("TargetFramework")?.EvaluatedValue ?? "";
            if (actualTfm != _context.Tfm)
            {
                Error(
                    $"Bazel expected TargetFramework {_context.Tfm}, but {_context.WorkspacePath(_context.ProjectFile)} is " +
                    $"configured to use TargetFramework {actualTfm}. Refusing to build as this will " +
                    $"produce unreachable output. Please reconfigure the project and/or BUILD file.");
                {
                    return false;
                }
            }
            return true;
        }

        private void WriteBazelProps()
        {
            if (_action != "restore" || !_context.ProjectBazelProps.Any()) return;

            var props = string.Join("\n        ",
                _context.ProjectBazelProps.Select((pair) => $"<{pair.Key}>{pair.Value}</{pair.Key}>"));
            File.WriteAllText(
                // msbuild auto-imports <project-file>.*.props from the restore dir
                Path.Combine(_context.MSBuild.RestoreDir, Path.GetFileName(_context.ProjectFile) + ".bazel.props"),
                $@"<Project>
    <PropertyGroup>
        {props}
    </PropertyGroup>
</Project>
"
            );
        }

        private ProjectCollection BeginBuild()
        {
            // GlobalProjectCollection loads EnvironmentVariables on Init. We use ExecRoot in the project files, we 
            // can't use MSBuildStartupDirectory because NuGet Restore uses a static graph restore which starts up a 
            // new process in the directory of the project file. We could set ExecRoot in the ProjectCollection Global
            // properties, but then we'd have to manage its value in the ConfigCache of the build manager later on.
            // Setting it here allows the project file to read it for paths and we don't have to clear it later.
            _context.SetEnvironment();

            var loggers = new List<ILogger>() {_msbuildLog};
            if (_context.DiagnosticsEnabled)
            {
                var path = _context.OutputPath(_context.Bazel.Label.Name + ".binlog");
                Debug($"added binlog {path}");
                var binlog = new BinaryLogger() {Parameters = path};
                loggers.Add(binlog);
            }

            var pc = new ProjectCollection(_context.MSBuild.GlobalProperties, loggers,
                ToolsetDefinitionLocations.Default);
            // pc.ProjectAdded += (sender, args) => { Diagnostics.WaitForDebugger(); };
            // pc.RegisterLoggers(loggers);
            // var pc = new ProjectCollection(new Dictionary<string, string>(), loggers, ToolsetDefinitionLocations.Default);
            // pc.RegisterLogger(_msbuildLog);
            var parameters = new BuildParameters(pc)
            {
                EnableNodeReuse = false,
                DetailedSummary = true,
                Loggers = pc.Loggers,
                ResetCaches = false,
                LogTaskInputs = _msbuildLog.Verbosity == LoggerVerbosity.Diagnostic,
                ProjectLoadSettings = ProjectLoadSettings.RecordEvaluatedItemElements,
                // cult-copy
                ToolsetDefinitionLocations =
                    Microsoft.Build.Evaluation.ToolsetDefinitionLocations.ConfigurationFile |
                    Microsoft.Build.Evaluation.ToolsetDefinitionLocations.Registry,
                // ProjectCacheDescriptor = ProjectCacheDescriptor.FromInstance(new MyCache(_targetGraph),
                //     new[] {new ProjectGraphEntryPoint(_context.ProjectFile)}, null, null)
            };


            if (_context.MSBuild.UseCaching)
            {
                parameters.OutputResultsCacheFile = _context.LabelPath(".cache");
                parameters.InputResultsCacheFiles = GetInputCaches();
                parameters.IsolateProjects = true;
            }

            _buildManager.BeginBuild(parameters);
            if (_msbuildLog.HasError)
            {
                Console.WriteLine("Failed to initialize build manager, please file an issue.");
            }
            else if (_context.MSBuild.UseCaching && parameters.InputResultsCacheFiles.Any())
            {
                _cacheManager.BeforeExecuteBuild();
            }

            return pc;
        }
        
        /// <summary>
        /// Restore writes absolute paths to project.assets.json and to .props and .targets files.
        /// We can't have absolute paths for these, because they will be re-used in future actions in a different
        /// sandbox or machine.
        /// For the assets file, we assume that the only build action that is looking at the file is MSBuild building
        /// the direct project. As such, the current directory will be the directory of this project file, so we'll
        /// make all the paths relative to the project file.
        /// For the xml files, we'll prepend MSBuildThisFileDirectory in case another project file is evaluating these
        /// files.
        /// </summary>
        private void FixRestoreOutputs()
        {
            foreach (var fileName in Directory.EnumerateFiles(_context.MSBuild.BaseIntermediateOutputPath))
            {
                var target = _context.Bazel.OutputBase;

                var isJson = fileName.EndsWith("json");
                var needsEscaping = isJson && Path.DirectorySeparatorChar == '\\';

                string Escape(string s) => s.Replace(@"\", @"\\");

                if (needsEscaping)
                    target = Escape(target);

                var contents = File.ReadAllText(fileName);
                using var output = new StreamWriter(File.Open(fileName, FileMode.Truncate));
                var index = 0;
                for (;;)
                {
                    var thisIndex = contents.IndexOf(target, index, StringComparison.Ordinal);
                    if (thisIndex == -1) break;
                    output.Write(contents[index..thisIndex]);

                    if (contents[thisIndex..(thisIndex + "sandbox".Length)] == "sandbox")
                        thisIndex = contents.IndexOf("execroot", index, StringComparison.Ordinal);

                    var endOfPath = contents.IndexOfAny(new[] {'"', ';', '<'}, thisIndex);

                    index = endOfPath;

                    var path = contents[thisIndex..endOfPath];

                    if (needsEscaping)
                        path = path.Replace(@"\\", @"\");

                    if (isJson)
                    {
                        path = Path.GetRelativePath(_context.ProjectDirectory, path);
                    }
                    else
                    {
                        path = Path.Combine("$(ExecRoot)", Path.GetRelativePath(_context.Bazel.ExecRoot, path));
                    }

                    if (needsEscaping)
                    {
                        path = Escape(path);
                    }

                    output.Write(path);
                }

                output.Write(contents[index..]);
                output.Flush();
            }
        }

        private string[] GetInputCaches()
        {
            var cacheManifest = _context.LabelPath(".input_caches");
            if (!File.Exists(cacheManifest)) return Array.Empty<string>();
            return File.ReadAllLines(cacheManifest);
        }

        private void CopyFiles(string filesKey, string destinationDirectory, bool trimPackage = false)
        {
            if (!_context.Command.NamedArgs.TryGetValue(filesKey, out var contentListString) ||
                contentListString == "") return;
            var contentList = contentListString.Split(";");
            var createdDirectories = new HashSet<string>();
            foreach (var filePath in contentList)
            {
                var src = new FileInfo(filePath);
                string destinationPath;
                if (filePath.StartsWith("external/"))
                {
                    destinationPath = filePath.Substring("external/".Length);
                }
                else if (trimPackage && filePath.StartsWith(_context.Bazel.Label.Package))
                {
                    destinationPath = filePath.Substring(_context.Bazel.Label.Package.Length + 1);
                }
                else
                {
                    destinationPath = Path.Combine(_context.Bazel.Label.Workspace, filePath);
                }

                var dest = new FileInfo(Path.Combine(destinationDirectory, destinationPath));

                if (!dest.Exists || src.LastWriteTime > dest.LastWriteTime)
                {
                    if (!createdDirectories.Contains(dest.DirectoryName!))
                    {
                        Directory.CreateDirectory(dest.DirectoryName!);
                        createdDirectories.Add(dest.DirectoryName!);
                    }

                    src.CopyTo(dest.FullName, true);
                }
            }
        }
    }

    internal class MyCache : ProjectCachePluginBase
    {
        private readonly TargetGraph? _targetGraph;

        public MyCache(TargetGraph? targetGraph)
        {
            _targetGraph = targetGraph;
        }

        public override Task BeginBuildAsync(CacheContext context, PluginLoggerBase logger, CancellationToken cancellationToken)
        {
            return Task.CompletedTask;
        }

        public override Task<CacheResult> GetCacheResultAsync(BuildRequestData buildRequest, PluginLoggerBase logger, CancellationToken cancellationToken)
        {
            if (_targetGraph == null)
                return Task.FromResult(CacheResult.IndicateNonCacheHit(CacheResultType.CacheMiss));

            _targetGraph.CanCache(buildRequest.ProjectFullPath, buildRequest.TargetNames);
            return Task.FromResult(CacheResult.IndicateNonCacheHit(CacheResultType.CacheMiss));
        }

        public override Task EndBuildAsync(PluginLoggerBase logger, CancellationToken cancellationToken)
        {
            return Task.CompletedTask;
        }
    }
}