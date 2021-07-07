using System;
using System.Collections.Generic;
using System.IO;

namespace RulesMSBuild.Tools.Builder
{
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
            
            var noWarn = "";
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
                ["ImportDirectoryBuildProps"] = "true",
                ["AlternateCommonProps"] = Path.Combine(propsDirectory!, "AlternateCommonProps.props"),
                ["ExecRoot"] = bazel.ExecRoot,
                ["BINDIR"] = bazel.BinDir,
                ["RestoreConfigFile"] = nuGetConfig,
                ["PublishDir"] = Path.Combine(OutputPath, "publish", tfm) + "/",
                ["UseAppHost"] = "false", // we'll basically be making our own via the launcher
                // msbuild's shared compilation is not compatible with sandboxing because it wll delegate compilation to
                // another process that won't have access to the sandbox requesting the build.
                ["UseSharedCompilation"] = "false",
                ["BazelBuild"] = "true",
            };
            switch (action)
            {
                case "restore":
                    Targets = new[] {"Restore"};
                    // this is auto-set by NuGet.targets in Restore when restoring a referenced project. If we don't set it
                    // ahead of time, there will be a cache miss on the restored project.
                    // https://github.com/NuGet/NuGet.Client/blob/21e2a87537cd9655b7f6599af013d447aa058e29/src/NuGet.Core/NuGet.Build.Tasks/NuGet.targets#L69
                    GlobalProperties["ExcludeRestorePackageImports"] = "true";
                    // enables a faster nuget restore compatible with isolated builds
                    // https://github.com/NuGet/NuGet.Client/blob/21e2a87537cd9655b7f6599af013d447aa058e29/src/NuGet.Core/NuGet.Build.Tasks/NuGet.targets#L1310
                    GlobalProperties["RestoreUseStaticGraphEvaluation"] = "true";
                    break;
                case "build":
                    Targets = new[]
                    {
                        // "GetTargetFrameworks",
                        "Build",
                        // "GetCopyToOutputDirectoryItems",
                        // "GetTargetPath",
                        // "GetNativeManifest",
                    };
                    break;
                case "publish":
                    Targets = new[] {"Publish"};
                    break;
                case "pack":
                    Targets = new[] {"Pack"};
                    GlobalProperties["NoBuild"] = "true";
                    break;
                default:
                    throw new ArgumentException($"Unknown action {action}");
            }
            BuildEnvironment["NoWarn"] = noWarn;
        }

        public Dictionary<string,string> GlobalProperties { get; set; }
        public string Configuration { get; }
        public Dictionary<string,string> BuildEnvironment { get; }
        public string[] Targets { get; }
        public string BaseIntermediateOutputPath { get; }
        public string RestoreDir => BaseIntermediateOutputPath;
        public string IntermediateOutputPath { get; }
        public string OutputPath { get; }
    }
}