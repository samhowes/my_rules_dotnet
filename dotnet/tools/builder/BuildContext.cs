#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

// https://stackoverflow.com/questions/64749385/predefined-type-system-runtime-compilerservices-isexternalinit-is-not-defined
namespace System.Runtime.CompilerServices
{
    internal static class IsExternalInit {}
}

namespace RulesMSBuild.Tools.Builder
{
    public class BuildContext
    {
        public Command Command { get; }

        public void SetEnvironment()
        {
            foreach (var (name, value) in MSBuild.BuildEnvironment)
            {
                Environment.SetEnvironmentVariable(name, value);
            }
        }

        public string LabelPath(string extension) => Path.Combine(Bazel.OutputDir, Bazel.Label.Name) + extension;
        public string OutputPath(params string[] subpath) => Path.Combine(subpath.Prepend(Bazel.OutputDir).ToArray());
        private string ExecPath(string subpath) => Path.Combine(Bazel.ExecRoot, subpath);
        public string BinPath(string subpath) => Path.Combine(Bazel.BinDir, subpath);
        // msbuild auto-imports <project-file>.*.props from the restore dir from Microsoft.Common.Props
        public string ProjectExtensionPath(string extension) =>
            Path.Combine(MSBuild.RestoreDir, Path.GetFileName(ProjectFile) + extension);
        
        // This should be Bazel.ExecRoot, as all the sdk tools are in the sandbox with the builder when it is running
        // MSBuild, however, MSBuild appears to not like the sandbox for the locations of the SDK files as it produces
        //  Microsoft.Common.CurrentVersion.targets(2182,5): error MSB3095: Invalid argument. "DefiningProjectDirectory"
        //  is a reserved item metadata, and cannot be modified or deleted.
        // when run with ExecRoot. After much debugging, this appears to happen somewhere in ResolveAssemblyReferences 
        // because MSBuild thinks it is necessary to copy metdata from one TaskItem for a referenced project to another 
        // TaskItem for that referenced project because it is missing metadata before being resolved. 
        private string ToolPath(string subpath) => Path.Combine(Bazel.OutputBase, subpath);
        
        public BuildContext(Command command)
        {
            Command = command;
            Bazel = new BazelContext(command);
            NuGetConfig = ToolPath(command.NamedArgs["nuget_config"]);
            Tfm = command.NamedArgs["tfm"];
            MSBuild = new MSBuildContext(
                command.Action,
                Bazel,
                ToolPath(command.NamedArgs["directory_bazel_props"]),
                NuGetConfig,
                Tfm,
                command.NamedArgs["configuration"]
                );

            IsExecutable = command.NamedArgs["output_type"] == "exe";
            
            SdkRoot = ToolPath(command.NamedArgs["sdk_root"]);
            
            ProjectFile = ExecPath(command.NamedArgs["project_file"]);
            ProjectDirectory = Path.GetDirectoryName(ProjectFile)!;
            
            IsTest = command.NamedArgs.TryGetValue("is_test", out _);

            ProjectBazelProps = new Dictionary<string, string>()
            {
                ["Workspace"] = Bazel.Label.Workspace
            };
            void TrySetProp(string arg, string name)
            {
                if (command.NamedArgs.TryGetValue(arg, out var value)
                    && !string.IsNullOrEmpty(value))
                    ProjectBazelProps![name] = value;
            }
            TrySetProp("version", "Version");
            TrySetProp("package_version", "PackageVersion");
            
            if (DiagnosticsEnabled)
            {
                MSBuild.BuildEnvironment["NUGET_SHOW_STACK"] = "true";
            }
        }

        public Dictionary<string,string> ProjectBazelProps { get; }
        public bool IsExecutable { get; }
        public string ProjectDirectory { get; }

        // ReSharper disable once InconsistentNaming
        public MSBuildContext MSBuild { get; }
        public string ProjectFile { get; }
        public BazelContext Bazel { get; }
        public string NuGetConfig { get; }
        public string Tfm { get; init; }
        public string SdkRoot { get; }
        public bool DiagnosticsEnabled { get; } = Environment.GetEnvironmentVariable("BUILD_DIAG") == "1";
        public bool IsTest { get; }
        public string? Version { get; }
        public string? PackageVersion { get; }
        public string WorkspacePath(string path) => "/" + path[Bazel.ExecRoot.Length..];
    }
    
    public class BazelContext
    {
        public class BazelLabel
        {
            public BazelLabel(string workspace, string package, string name)
            {
                Workspace = workspace;
                Package = package;
                Name = name;
            }

            public string Workspace { get; }
            public string Package { get; }
            public string Name { get; }
        }
        public BazelContext(Command command)
        {
            OutputBase = command.NamedArgs["bazel_output_base"];
            // bazel invokes us at the exec root
            ExecRoot = Directory.GetCurrentDirectory();
            // Suffix = ExecRoot[OutputBase.Length..];
            BinDir = Path.Combine(ExecRoot, command.NamedArgs["bazel_bin_dir"]);
                
            Label = new BazelLabel(
                command.NamedArgs["workspace"], 
                command.NamedArgs["package"], 
                command.NamedArgs["label_name"]);

            OutputDir = Path.Combine(BinDir, Label.Package);
        }

        public string OutputBase { get; }
        public string OutputDir { get; }
        public BazelLabel Label { get; }
        public string BinDir { get; }
        public string ExecRoot { get; }
            
    }
    
    // ReSharper disable once InconsistentNaming
    public class MSBuildContext
    {
        public MSBuildContext(string action, 
            BazelContext bazel, 
            string directoryBazelPropsPath, 
            string nuGetConfig, 
            string tfm,
            string configuration)
        {
            Configuration = configuration;
            OutputPath = bazel.OutputDir;
            BaseIntermediateOutputPath = Path.Combine(OutputPath, "restore");
            IntermediateOutputPath = Path.Combine(OutputPath, "obj");

            var propsDirectory = Path.GetDirectoryName(directoryBazelPropsPath);
            
            var noWarn = "NU1603;MSB3277";
            GlobalProperties = new Dictionary<string, string>
            {
                ["Configuration"] = Configuration,
                ["BuildProjectReferences"] = "false"
            };

            switch (Configuration.ToLower())
            {
                case "debug":
                    GlobalProperties["DebugSymbols"] = "true";
                    break;
                case "release":
                case "fastbuild":
                    GlobalProperties["DebugSymbols"] = "false";
                    GlobalProperties["DebugType"] = "none";
                    break;
            }

            BuildEnvironment = new Dictionary<string, string>()
            {
                ["AlternateCommonProps"] = Path.Combine(propsDirectory!, "AlternateCommonProps.props"),
                ["ExecRoot"] = bazel.ExecRoot,
                ["BINDIR"] = bazel.BinDir,
                ["RestoreConfigFile"] = nuGetConfig,
                ["PublishDir"] = Path.Combine(OutputPath, "publish", tfm) + "/",
                ["UseAppHost"] = "false", // we'll basically be making our own via the launcher
                // msbuild's shared compilation is not compatible with sandboxing because it wll delegate compilation to aonother 
                // process that won't have access to the sandbox requesting the build.
                ["UseSharedCompilation"] = "false",
                ["BazelBuild"] = "true",
                ["ImportDirectoryBuildProps"] = "true",
            };

            switch (action)
            {
                case "restore":
                    Targets = new[] {"Restore"};
                    // we aren't using restore's cache files in the Build actions, so different global properties are fine

                    // this is auto-set by NuGet.targets in Restore when restoring a referenced project. If we don't set it
                    // ahead of time, there will be a cache miss on the restored project.
                    // https://github.com/NuGet/NuGet.Client/blob/21e2a87537cd9655b7f6599af013d447aa058e29/src/NuGet.Core/NuGet.Build.Tasks/NuGet.targets#L69
                    GlobalProperties["ExcludeRestorePackageImports"] = "true";
                    // enables a faster nuget restore compatible with isolated builds
                    // https://github.com/NuGet/NuGet.Client/blob/21e2a87537cd9655b7f6599af013d447aa058e29/src/NuGet.Core/NuGet.Build.Tasks/NuGet.targets#L1310
                    GlobalProperties["RestoreUseStaticGraphEvaluation"] = "true";
                    break;
                case "build":
                    // https://github.com/dotnet/msbuild/issues/5204
                    Requests = new[]
                    {
                        // for some reason, setting this in restore results in:
                        // NuGet.RestoreEx.targets(19,5): error : Object reference not set to an instance of an object.
                        // that's fine though, we're not really using the caching from that action
                        // setting this as a global property for the project allows nuget pack to re-use the cache produced
                        // from the build action, because the Pack target builds certain child targets with this as a global
                        // property
                        // new BuildRequest(new[]
                        // {
                        //     "Build",
                        //     "GetCopyToOutputDirectoryItems"
                        // }, ("TargetFramework", tfm)),
                        new BuildRequest(new[]
                        {
                            // "ResolveReferences",
                            "GetTargetFrameworks",
                            "Build",
                            "GetCopyToOutputDirectoryItems",
                            "GetTargetPath",
                            "GetNativeManifest",
                            // included so Publish doesn't produce MSB3088
                            // "ResolveAssemblyReferences",
                        })
                    };
                    break;
                case "publish":
                    Targets = new[] {"Publish"};
                    
                    
                    UseCaching = false;
                    // msbuild is going to evaluate all the project files anyways, and we can't use any input caches
                    // from the builds because for some reason the caches discard some items that are computed
                    // so just do a graph build. It might be faster to use publish caches, but this 
                    // current implementation is quite slower than a standard `dotnet publish /graph` anyways, so 
                    // i'll be taking more of a look at optimizations later. 
                    GraphBuild = true;
                    // Setting this as a global property invalidates the input cache files from the build action.
                    // MSBuild will do that anyway because it's going to load a config from the cache that matches the entry
                    // project, but MSBuild does *not* serialize project state after a build so that
                    // BuildRequestConfiguration instance will not have a ProjectInstance attached to it, and MSBuild will
                    // assume it ran into https://github.com/dotnet/msbuild/issues/1748, and set a global "Dummy" property
                    // to explicitly invalidate the cache. We can set BuildRequestDataFlags.ReplaceExistingProjectInstance
                    // to not invalidate the cache, but then publish won't have the right items calculated (at least
                    // Content items will be missing), and we won't get the publish output we expect.
                    // To get the caching we want we'd have to somehow persist ProjectInstance to disk from the build action
                    // which appears to be possible via the ITranslatable interface, but all of that code has `internal`
                    // visibility in the MSBuild assembly, and there is no one single method that we can target to persist
                    // it to disk, but a collection of methods and classes. Might be doable with more knowledge of their
                    // codebase, but seems rather brittle and hacky with the knowledge I currently have.

                    // tl;dr: we get a performance hit because we have to re-evaluate the project file, but for now,
                    // this is how we get the full proper output.
                    
                    // Required, otherwise publish will try to re-build and discard the previous build results
                    GlobalProperties["NoBuild"] = "true";
                    // Publish re-executes the ResolveAssemblyReferences task, which uses the same .cache file as the build
                    // action. Since we'll have all the output from the build action, this file will be readonly in the
                    // sandbox. MSBuild opens this with Read+Write, so it will get an Access Denied exception and produce
                    // a warning when trying to open that file. Suppress that warning.
                    noWarn += ";MSB3088;MSB3101";
                    
                    break;
                case "pack":
                    Targets = new[] {"Pack"};
                    GraphBuild = true;
                    GlobalProperties["NoBuild"] = "true";
                    UseCaching = false;
                    break;
                default:
                    throw new ArgumentException($"Unknown action {action}");
            }
            GlobalProperties["NoWarn"] = noWarn;

            if (Requests == null)
            {
                Requests = new[] {new BuildRequest(Targets!)};
            }
        }

        public BuildRequest[] Requests { get; }

        public Dictionary<string,string> GlobalProperties { get; set; }

        public string Configuration { get; }

        public Dictionary<string,string> BuildEnvironment { get; }

        public bool GraphBuild { get; }

        public bool UseCaching { get; } = true;

        public string[]? Targets { get; }

        public string BaseIntermediateOutputPath { get; }
        public string RestoreDir => BaseIntermediateOutputPath;
        public string IntermediateOutputPath { get; }
        public string OutputPath { get; }

        public class BuildRequest
        {
            public string[] Targets { get; }
            public Dictionary<string,string> Properties { get; }
            public BuildRequest(string[] targets, params (string name, string value)[] properties)
            {
                Targets = targets;
                Properties =
                    new Dictionary<string, string>(properties.Select(p =>
                        new KeyValuePair<string, string>(p.name, p.value)));
            }
        }
    }
}