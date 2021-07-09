using System.IO;
using System.Text;
using Microsoft.Build;

namespace RulesMSBuild.Tools.Builder
{
    public readonly struct PathMappingInternable : IInternable
    {
        private readonly PathMapper _pathMapper;
        private readonly IInternable _wrapped;

        public PathMappingInternable(IInternable wrapped, PathMapper pathMapper)
        {
            _wrapped = wrapped;
            _pathMapper = pathMapper;
        }
        
        public string ExpensiveConvertToString()
        {
            var original = _wrapped.ExpensiveConvertToString();
            return _pathMapper.ReplacePath(original);
        }

        public bool StartsWithStringByOrdinalComparison(string other) =>
            _wrapped.StartsWithStringByOrdinalComparison(other);

        public bool ReferenceEquals(string other) => _wrapped.ReferenceEquals(other);

        public int Length => _wrapped.Length;

        public char this[int index] => _wrapped[index];
    }

    public class PathMappingInterner : ICustomInterner
    {
        private readonly PathMapper _pathMapper;

        public PathMappingInterner(PathMapper pathMapper)
        {
            _pathMapper = pathMapper;
        }
        
        public string CharArrayToString(char[] candidate, int count)
        {
            return OpportunisticIntern.InternableToString(
                new PathMappingInternable(new CharArrayInternTarget(candidate, count), _pathMapper));
        }

        public string StringBuilderToString(StringBuilder candidate)
        {
            return OpportunisticIntern.InternableToString(
                new PathMappingInternable(new StringBuilderInternTarget(candidate), _pathMapper));
        }
    }
    
    public class PathMappingReader : BinaryReader
    {
        public PathMappingReader(Stream input) : base(input)
        {
        }

        public PathMappingReader(Stream input, Encoding encoding) : base(input, encoding)
        {
        }

        public PathMappingReader(Stream input, Encoding encoding, bool leaveOpen) : base(input, encoding, leaveOpen)
        {
        }
    }
    
    public class PathMappingBinaryWriter : BinaryWriter
    {
        private readonly PathMapper _pathMapper;

        public PathMappingBinaryWriter(Stream stream, PathMapper pathMapper) : base(stream)
        {
            _pathMapper = pathMapper;
        }

        public override void Write(string value)
        {
            base.Write(_pathMapper.ReplacePath(value));
        }
    }
}