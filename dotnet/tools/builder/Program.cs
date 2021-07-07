using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.Build.Locator;
using static RulesMSBuild.Tools.Builder.BazelLogger;

namespace RulesMSBuild.Tools.Builder
{
    public class Command
    {
        public string Action;
        public List<string> PositionalArgs = new List<string>();
        public Dictionary<string, string> NamedArgs = new Dictionary<string, string>();
    }

    public class Program
    {
        private static Regex MsBuildVariableRegex = new Regex(@"\$\((\w+)\)", RegexOptions.Compiled);
        
        static int Main(string[] args)
        {
            if (DebugEnabled)
            {
                Debug($"Received {args.Length} arguments: {string.Join(" ", args)}");
            }
            
            var command = ParseArgs(args);

            switch (command.Action)
            {
                case "launcher":
                    return MakeLauncher(command);
                
                case "pack":
                case "restore":
                case "publish":
                case "build":
                    return Build(command);
                    
                default:
                    return Fail($"Unknown command: {command.Action}");
                    
            }
        }
        private static Command ParseArgs(string[] args)
        {
            var command = new Command {Action = args[0]};
            ParseArgsImpl(args, 1, command);
            return command;
        }

        private static void ParseArgsImpl(string[] args, int start, Command command)
        {
            for (var i = start; i < args.Length; i++)
            {
                var arg = args[i];
                if (arg == "@file")
                {
                    var fileArgs = File.ReadAllLines(args[i + 1])
                        .SelectMany(l => l.Split(' '))
                        .ToArray();
                    ParseArgsImpl(fileArgs, 0, command);
                    i++;
                    continue;
                }
                
                if (arg.Length == 0 || arg[0] != '-')
                {
                    command.PositionalArgs.Add(arg);
                    continue;
                }

                // assume a well formed array of args in the form [`--name` `value`]
                var name = arg[2..];
                var value = args[i + 1];
                command.NamedArgs[name] = value;
                i++;
            }
        }

        private static int Build(Command command)
        {
            var context = new BuildContext(command);
            var dotNetSdkPath = context.SdkRoot + Path.DirectorySeparatorChar;
            foreach (KeyValuePair<string, string> keyValuePair in new Dictionary<string, string>()
            {
                ["MSBUILD_EXE_PATH"] = dotNetSdkPath + "MSBuild.dll",
                ["MSBuildExtensionsPath"] = dotNetSdkPath,
                ["MSBuildSDKsPath"] = dotNetSdkPath + "Sdks"
            })
                Environment.SetEnvironmentVariable(keyValuePair.Key, keyValuePair.Value);
            
            MSBuildLocator.RegisterMSBuildPath(context.SdkRoot);
            var builder = new Builder(context);
            return builder.Build();
        }

        private static int MakeLauncher(Command command)
        {
            var factory = new LauncherFactory();
            return factory.Create(command.PositionalArgs.ToArray());
        }
    }
}