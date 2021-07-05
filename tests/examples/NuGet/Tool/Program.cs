using System;
using System.IO;
using RulesMSBuild.Tools.Bazel;

namespace Tool
{
    class Program
    {
        static void Main(string[] args)
        {
            var runfiles = Runfiles.CreateNuget();
            var foo = runfiles.Rlocation("rules_msbuild/tests/examples/NuGet/Tool/foo.txt");
            Console.WriteLine("runfile contents: " + File.ReadAllText(foo));
        }
    }
}
