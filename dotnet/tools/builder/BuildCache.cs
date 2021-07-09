using System.Collections.Generic;
using System.IO;
using Microsoft.Build;
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
        private ProjectInstance _project;
        private readonly PathMapper _pathMapper;
        private readonly Files _files;

        public BuildCache(CacheManifest manifest, PathMapper pathMapper, Files files)
        {
            _manifest = manifest;
            _pathMapper = pathMapper;
            _files = files;
        }

        public void RecordResult(BuildResult buildResult)
        {
            var project = buildResult.ProjectStateAfterBuild;
            _project = project;
        }

        public void Save(string path)
        {
            using var stream = _files.Create(path);;
            var writer = new PathMappingBinaryWriter(stream, _pathMapper);
            var translator = new BinaryTranslator.BinaryWriteTranslator(stream, writer);
            
            translator.Translate(ref _project, ProjectInstance.FactoryForDeserialization);
        }

        public void LoadProject(string path)
        {
            using var stream = File.OpenRead(path);
            var reader = InterningBinaryReader.Create(stream, null);
            reader.OpportunisticIntern = new PathMappingInterner(_pathMapper);
            var translator = new BinaryTranslator.BinaryReadTranslator(stream, null);
        }
    }
}