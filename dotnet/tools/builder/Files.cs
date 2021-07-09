using System.Collections.Generic;
using System.IO;

namespace RulesMSBuild.Tools.Builder
{
    public class Files
    {
        public virtual string GetContents(string path) => File.ReadAllText(path);
        public virtual void WriteContents(string path, string contents) => File.WriteAllText(path, contents);
        public virtual IEnumerable<string> GetFiles(string path) => Directory.EnumerateFiles(path);
        public virtual IEnumerable<string> GetDirectories(string path) => Directory.EnumerateDirectories(path);
        public virtual Stream Create(string path) => File.Create(path);
    }
}