﻿using System;

namespace RulesMSBuild.Tests.NuGet.Transitive
{
    class Program
    {
        static void Main(string[] args)
        {
            var obj = JsonParser.Parse(@"{""foo"": ""bar""}");
            Console.WriteLine(obj.Foo);
        }
    }
}
