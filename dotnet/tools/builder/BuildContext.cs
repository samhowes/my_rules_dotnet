#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Build.BackEnd;

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
        public class BazelLabel : ITranslatable
        {
            public BazelLabel(string workspace, string package, string name)
            {
                Workspace = workspace;
                Package = package;
                Name = name;
            }

            public string Workspace = null!;
            public string Package = null!;
            public string Name = null!;

            public BazelLabel(){}

            public void Translate(ITranslator translator)
            {
                translator.Translate(ref Workspace);
                translator.Translate(ref Package);
                translator.Translate(ref Name);
            }
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
}