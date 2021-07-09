using System.IO;
using System.Text.RegularExpressions;

namespace RulesMSBuild.Tools.Builder
{
    public class PathMapper
    {
        private readonly BazelContext _bazel;
        private readonly Regex _regex;

        protected PathMapper(){} // for Moq
        public PathMapper(BazelContext bazel)
        {
            _bazel = bazel;

            var execRoot = bazel.ExecRoot[(bazel.OutputBase.Length)..];

            _regex = new Regex($"({Regex.Escape(bazel.OutputBase)})({Regex.Escape(execRoot)})?/",
                RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.Multiline);
        }

        public virtual string ReplacePath(string path) => _regex.Replace(path, "");
    }
}