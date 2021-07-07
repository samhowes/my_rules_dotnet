 using System;

namespace RulesMSBuild.Tools.Builder
{
    public static class BazelLogger
    {
        public static int Fail(string message)
        {
            Console.Error.WriteLine("[Builder] " + message);
            Console.Error.Flush();
            Environment.Exit(1);
            return 1; // weird. Oh well.
        }
        public static bool DebugEnabled = Environment.GetEnvironmentVariable("BUILD_DIAG") != null;
        public static bool VerboseEnabled = Environment.GetEnvironmentVariable("DOTNET_BUILDER_DEBUG") == "v";

        public static void Verbose(string message)
        {
            if (!VerboseEnabled) return;
            Console.WriteLine("[Verbose] " + message);
        }
        public static void Debug(string message)
        {
            if (!DebugEnabled) return;
            Console.WriteLine("[Debug] " + message);
        }

        public static void Error(string s)
        {
            Console.Error.WriteLine(s);
            Console.Error.Flush();
        }
    }
}