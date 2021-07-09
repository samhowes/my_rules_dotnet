#nullable enable
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Xml;
using FluentAssertions;
using Microsoft.Build.Evaluation;
using Microsoft.Build.Execution;
using Moq;
using RulesMSBuild.Tools.Builder;
using Xunit;

namespace RulesMSBuild.Tests.Tools
{
    public class UnclosableMemoryStream : MemoryStream
    {
        public override void Close()
        {
        }

        protected override void Dispose(bool disposing)
        {
        }

        public override ValueTask DisposeAsync()
        {
            return ValueTask.CompletedTask;
        }

        public void ReallyDispose() => base.Dispose();
    }
    
    public class BuildCacheTests : IDisposable
    {
        private readonly BuildCache _cache;
        private readonly Mock<Files> _files;
        private Dictionary<object, object?> _originalEnv;

        public BuildCacheTests()
        {
            var replacer = new Mock<PathMapper>();
            replacer.Setup(p => p.ReplacePath(It.IsAny<string>()))
                .Returns<string>(str => str.Length > 0 && str.StartsWith('/') ? "YAY" : str);
            
            _files = new Mock<Files>();
            _cache = new BuildCache(new CacheManifest(), replacer.Object, _files.Object);
            _originalEnv = new Dictionary<object, object?>();
            foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
                if (entry.Value is string str && str.Contains("/"))
                {
                    _originalEnv[entry.Key] = entry.Value;
                    Environment.SetEnvironmentVariable((entry.Key as string)!, null);
                }
            
            ProjectCollection.GlobalProjectCollection.EnvironmentProperties.Clear();
        }

        
        
        [Fact]
        public void SaveFile_ReplacesPaths()
        {
            var written = new UnclosableMemoryStream();
            _files.Setup(f => f.Create(It.IsAny<string>())).Returns(written);
            
            var project = new Project(XmlReader.Create(new StringReader(@"
<Project>
    <PropertyGroup>
        <FilePath>/foo/bar</FilePath>
    </PropertyGroup>
</Project>
")));
            
            _cache.RecordResult(new BuildResult()
            {
                ProjectStateAfterBuild = project.CreateProjectInstance()
            });
            
            _cache.Save("foo");

            written.Length.Should().BeGreaterThan(0);
            written.Seek(0, SeekOrigin.Begin);
            var str = new StreamReader(written).ReadToEnd();
            str.Should().Contain("YAY");
            str.Should().NotContain("foo/bar");
            str.Should().NotContain("/");
        }

        public void Dispose()
        {
            foreach (var (key, value) in _originalEnv)
            {
                 Environment.SetEnvironmentVariable((key as string)!, value as string);
            }
        }
    }
}
