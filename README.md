# Dotnet Rules for Bazel

| Windows                                                                                                                                                                                                                                                        | Mac                                                                                                                                                                                                                                                    | Linux                                                                                                                                                                                                                                                      |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [![Build Status](https://dev.azure.com/samhowes/my_rules_dotnet/_apis/build/status/samhowes.my_rules_dotnet?branchName=master&jobName=windows)](https://dev.azure.com/samhowes/my_rules_dotnet/_build/latest?definitionId=3&branchName=master&jobName=windows) | [![Build Status](https://dev.azure.com/samhowes/my_rules_dotnet/_apis/build/status/samhowes.my_rules_dotnet?branchName=master&jobName=mac)](https://dev.azure.com/samhowes/my_rules_dotnet/_build/latest?definitionId=3&branchName=master&jobName=mac) | [![Build Status](https://dev.azure.com/samhowes/my_rules_dotnet/_apis/build/status/samhowes.my_rules_dotnet?branchName=master&jobName=linux)](https://dev.azure.com/samhowes/my_rules_dotnet/_build/latest?definitionId=3&branchName=master&jobName=linux) |

<!--
Links
 -->

This is currently a learning, work-in-progress, repository while I get familiar with
[extending Bazel](https://docs.bazel.build/versions/master/skylark/concepts.html). If you are
looking for a working implementation of rules for dotnet head over to
[io_bazel_rules_dotnet](https://github.com/bazelbuild/rules_dotnet).

# Contents

-   [Features](#features)
-   [Usage](#usage)
-   [Background](#setup)
    -   [Resources](#resources)
-   [Goals](#goals)
-   [Limitations](#limitations)

## Quick links

-   [Repository Rules Reference](./dotnet/repository_rules.md)
-   [NuGet Management](./dotnet/nuget.md)
-   [Understanding the Build](./dotnet/understanding.md)

# Features

-   WORKSPACE Configuration
-   NuGet Package management
-   `dotnet build` Feature parity
    -   See open issues for feature gaps

# Usage

```python
# //WORKSPACE
load("@bazel_tools//tools/build_defs/repo:git.bzl", "http_archive")

git_repository(
    name = "my_rules_dotnet",
    tag = "stable",
    remote = "https://github.com/samhowes/my_rules_dotnet"
)

load("@my_rules_dotnet//dotnet:py_deps.bzl", "dotnet_register_toolchains", "dotnet_rules_dependencies")

dotnet_rules_dependencies()
# TODO(#10) allow user-specified sdks
# See https://dotnet.microsoft.com/download/dotnet for valid versions
dotnet_register_toolchains(version = "3.1.100")
```

```python
# //hello/BUILD
load("@my_rules_dotnet//dotnet:def.bzl", "dotnet_binary")

dotnet_binary(
    name = "hello",
    srcs = ["Program.cs"],
)
```

`bazel build //hello`

# Background

This is a fresh implementation of bazel rules for dotnet that uses the
[dotnet cli](https://docs.microsoft.com/en-us/dotnet/core/tools/dotnet) to do the building. This
repository started because I was interested in modifying
[bazelbuild/rules_dotnet](https://github.com/bazelbuild/rules_dotnet) but wasn't sure what approach
to take modifying existing code to get it to the state I was interested in. Instead I started a
fresh implementation so I could learn the ins and outs of bazel without working around existing
code.

It appears that [io_bazel_rules_dotnet](https://github.com/bazelbuild/rules_dotnet) started out
[fully supporting .NET, mono, and .NET Core](https://github.com/bazelbuild/rules_dotnet/pull/208)
but dropped support. At the time of writing I am uncertain what impact that has had on the code.

Currently, only .NET Core SDK 3.1.100 has been used in development. Given the format of Dotnet core,
there should not be issues with a different SDK Version, but other versions are untested.

## Resources

1. This implementation is styled based after the implementation of
   [rules_go](https://github.com/bazelbuild/rules_go)
1. JayConrod (from rules_go) did a great intro to implementing bazel rules in his blog post:
   [Writing Bazel rules](https://jayconrod.com/posts/106/writing-bazel-rules--simple-binary-rule)
1. Management of NuGet packages derived from
   [rules_jvm_external](https://github.com/bazelbuild/rules_jvm_external)

# Goals

### Context given Existing work

Goals for these rules vs the current implementation at
[io_bazel_rules_dotnet](https://github.com/bazelbuild/rules_dotnet). Existing work may have good
reasons for the current implementation, but being unfamiliar with Bazel, I am uncertain whether the
goals described below _should_ be implemented.

For each goal below io_bazel_rules_dotnet's implementation could

1. Have a different goal in mind that my goals compromise
1. Have chosen an implementation that was more compatible with .NET and Mono
1. Have chosen a better implementation given more experience with Bazel

## Goal #1: Simple translation from .csproj to BUILD.bazel

Handwriting a BUILD file from a `dotnet new` .csproj file should be intuitive and ergonomic,
adhering to both Bazel and .NET conventions.

The "modern" .csproj generated by the `dotnet new` command with dotnet core takes a very slim
approach to project management that is very similar to a BUILD.bazel file. The csproj now mostly
just lists dependencies using some MsBuild keywords/attributes. Each attribute/target/item group
will be attempted to moved to a simple bazel primitive if available.

The current implementation actually fills in a
[template .proj file](dotnet/private/msbuild/compile.tpl.proj) with the attributes specified on the
build rule. This may be moved to a custom "builder" approach that integrates with
[MsBuild's BuildManager Class](https://docs.microsoft.com/en-us/dotnet/api/microsoft.build.execution.buildmanager?view=msbuild-16-netcore)
similar to what
[io_bazel_rules_go is doing](https://github.com/bazelbuild/rules_go/tree/master/go/tools/builders).

The following translations are attempted:

1. `Project Sdk="<sdk>"` => TODO(#3)
1. Condition Attributes:
   [Starlark macros](https://docs.bazel.build/versions/master/skylark/macros.html) should be written
   by the user for condition functionality.
1. MsBuild
   [`PropertyGroup`](https://docs.microsoft.com/en-us/visualstudio/msbuild/propertygroup-element-msbuild?view=vs-2019)
   items ("Magic" properties)
    1. `TargetFramework` => Attribute of Bazel Rule
1. [ItemGroup](https://docs.microsoft.com/en-us/visualstudio/msbuild/itemgroup-element-msbuild?view=vs-2019)
    1. Implicit compilation of the entire folder and all subdirectories: the user can specify
       `srcs = glob([**/*.cs])`
    1. `Compile` => `srcs`
    1. `Content` => `data`
    1. `Res` => TODO(#1)
    1. `None` ignored
    1. `ProjectReference` => `deps` TODO(#5)
    1. `PackageReference` => `deps` TODO(#4)

Using the above translations, the following ConsoleApp.csproj file:

```xml
<Project Sdk="Microsoft.NET.Sdk">
	<PropertyGroup>
		<TargetFramework>netcoreapp3.1</TargetFramework>
	</PropertyGroup>

	<ItemGroup>
        <Content Include="testdata\**">
			<CopyToOutputDirectory>Always</CopyToOutputDirectory>
		</Content>

		<None Remove="test.txt" />
	</ItemGroup>

	<ItemGroup>
		<PackageReference Include="CommandLineParser" Version="2.8.0" />
	</ItemGroup>

	<ItemGroup>
		<ProjectReference Include="..\ClassLibrary\ClassLibrary.csproj" />
	</ItemGroup>
</Project>
```

Can be converted to:

```python
# //foo/ConsoleApp/BUILD
load("@my_rules_dotnet//dotnet:defs.bzl", "dotnet_binary")

dotnet_binary(
    name = "ConsoleApp",
    target_framework = "netcoreapp3.1",
    data = glob(["testdata/**/*"]), # TODO(#6)
    srcs = glob(["**/*.cs"]),
    deps = [
        "@nuget//commandlineparser", # TODO(#4)
        "//foo/ClassLibrary", # TODO(#5)
    ]
)
```

Given the workspace file:

```python
# other setup omitted
load("@my_rules_dotnet//dotnet:defs.bzl", "nuget_restore") # TODO(#4)
nuget_restore(
    lock_file = ":nuget_package_lock.json",
    packages = [
        "CommandLineParser:2.8.0",
    ],
)
```

## Goal #2: Utilzation of NuGet package lock for Package Management

The Package Management solution (#4) is not implemented or designed yet, but now that
[NuGet has implemented package locks](https://devblogs.microsoft.com/nuget/enable-repeatable-package-restores-using-a-lock-file/)
an approach similar to [rules_jvm_external](https://github.com/bazelbuild/rules_jvm_external#usage)
appears to be possible. NuGet is still developing the spec for
[Repository wide package management](https://github.com/NuGet/Home/wiki/Centrally-managing-NuGet-package-versions)
though, so there may be some unforseen roadbloacks to that implementation in my_rules_dotnet.

This was my initial motivation for contributing to rules_dotnet: checking large amounts ofgenerated
starlark code into the repository such as
[`nuget.bzl`](https://github.com/bazelbuild/rules_dotnet/blob/master/dotnet/private/deps/nuget.bzl)
is viewed as undesirable. This repository is essentially a proving ground for that package
management solution which I hope to merge into io_bazel_rules_dotnet.

## Goal #3: Merge all developed code with rules_dotnet

Ideally, there is one implementation of bazel rules that downloads and uses the dotnet sdk for
building with bazel that accounts for all use cases of the dotnet sdk. Once an implementation is
settled on, the goal is to merge the strategies used in this repository with rules_dotnet.

Key Differences in my_rules_dotnet and io_bazel_rules_dotnet:

1. "High Level" build vs "Low Level" compilation
    1. my_rules_dotnet rules like `dotnet_binary` utilize `dotnet build` to do the building, package
       and framework dependency detection loosely treating `dotnet` as the "compiler" and invokes a
       "high level" MsBuild that invokes MsBuild targets defined by the dotnet sdk and .targets
       files.
    1. io_bazel_rules_dotnet rules like `csharp_binary` utilizes some NuGet packages provide by the
       dotnet framework to do some dependency detection, but ultimately drops down to directly
       invoke the Roslyn compiler
       [`csc.exe`](https://github.com/bazelbuild/rules_dotnet/blob/master/dotnet/private/actions/assembly_core.bzl#L76)

These rules should be compatible and coexist with each other, but I wanted to settle on my fully
desired design before attempting to modify the core strategy of io*bazel_rules_dotnet. It could be
that io_bazel_rules_dotnet prefers to stay with strictly "csharp*\*" rules that compile the actual
C# rather than invoking MsBuild via the dotnet cli. If that becomse the case, this repository will
likely consider discussing naming changes such as being renamed to "rules_msbuild" and hopefully
moving to `bazel/rules_msbuild` under the workspace moniker of `io_bazel_rules_msbuild`.

Much work is still to be done to be a complete "rules" implementation though.

## Goal #4: Provide seamless migration from Visual Studio builds

I have been brought to Bazel because I work in dotnet core and am currently managing:

-   3 split repositories
-   ~5 Solution files
-   ~100 + ~10 + ~20 csproj files
-   ~10 sqlproj files
    -   Each sqlproj dacpac has an accompanying Entity Framework Core DbContext
-   ~2 + ~3 + ~1 angular projects
-   E2E tests written in Protractor (typescript) that seed the database using dotnet code, and runs
    the angular app via typescript both at build time using an In memory Sqlite database, and at
    release time with SqlServer.
-   ~15 minute CI time to dicover I forgot to remove `fdescribe` from my javascript E2E test that I
    was running locally

The longer I have this code separated, the more duplication of work my team ends up doing.

The more we integrate our code into one repository and the more projects depend on each other, the
longer it takes to load everything in Visual Studio, and the more I wish we had fewer projects that
depend on each other.

I have worked in Bazel before, but my team has not. My goal is to provide them with a seamless
transition to Bazel that improves build times and code management without impacting workflows using
Visual Studio. A bazel implementation of rules for dotnet is the first necessary component, but
integration with Visual Studio is an obvious second component for a team working in Dotnet. I am
hoping to work on a Visual Studio extension that tightly integrates with these rules much like the
[IntelliJ Plugin](https://ij.bazel.build/).

# Limitations

1. #17: Multiple donet\_\* targets cannot exist in the same directory.
