using System.Collections.Generic;
using Microsoft.Build.BackEnd;
using Microsoft.Build.Execution;

namespace RulesMSBuild.Tools.Builder
{
    public class LabelResult : ITranslatable
    {
        public BazelContext.BazelLabel Label;
        public ProjectInstance Project;
        public BuildResult BuildResult;
        
        public void Translate(ITranslator translator)
        {
            translator.Translate(ref Label);
            translator.Translate(ref Project, ProjectInstance.FactoryForDeserialization);
            translator.Translate(ref BuildResult);
        }
    }

    public class CacheManifest
    {
        public Dictionary<string, string> Projects { get; set; }
        public Dictionary<string, string> ProjectResults { get; set; }
    }
    
    public class BuildCache
    {
        private readonly CacheManifest _manifest;

        public BuildCache(CacheManifest manifest)
        {
            _manifest = manifest;
        }
    }
}