"""Dotnet Providers"""

DotnetRestoreInfo = provider(
    doc = "todo",
    fields = {
        "project_file": "",
        "restore_dir": "",
        "target_framework": "",
        "dep_files": "",
        "cache": "",
    },
)

DotnetLibraryInfo = provider(
    doc = "Contains information about a Dotnet library",
    fields = {
        "assembly": "The primary assembly that was compiled",
        "output_dir": "The msbuild output directory as a declared file",
        "runfiles": "runfiles",
        "build_cache": "",
        "build_caches": "depset of build_cache and all build_caches this library depends on",
        "srcs": "depset of the transitive closure of all source files this library depends on",
        "content": "depset of non-compiled files needed in the output directory as a sibling of the output assembly",
        "restore": "DotnetRestoreInfo",
        "dep_files": "depset of all files this library depends on",
        "intermediate_dir": "",
    },
)

NuGetPackageInfo = provider(
    doc = "Package restore information",
    fields = {
        "name": "Package name",
        "frameworks": (
            "A struct from a cannonical tfm (e.g. netcoreapp3.1) to NuGetFetchedPackageFrameworkInfo providers " +
            "for framework specific package information. The members of this struct are defined by the *package consumers*, not by " +
            "the package. i.e. if the package is a netstandard2.0 package, but the consuming target is targeting netcoreapp3.1, then " +
            "the key `netcoreapp3.1` will exist in this struct, *not* netstandard2.0. This matches up with the packages.lock.json and " +
            "allows package consumers to easily access the deps specific to their framework."
        ),
    },
)

NuGetPackageVersionInfo = provider(
    doc = "A specific restored version of a NuGet package",
    fields = {
        "version": "string representing the nuget package version: ex. `1.6-preview1`",
        "all_files": "depset of All the files that comprise the nuget package. NuGet enumerates these for us each time " +
                     "it does a restore.",
    },
)

NuGetFilegroupInfo = provider(
    doc = "A group of files for a NuGet package.",
    fields = {
        "tfm": "the tfm of this filegroup",
        "version": "the version of the nuget package that tfm depends on",
        "all_dep_files": "depset of all the files that this filegroup depends on",
    },
)

DotnetContextInfo = provider(
    doc = "A dotnet context",
    fields = {},
)

def MSBuildSdk(name, version):
    """An msbuild sdk happens to actually be a NuGetPackage

    https://github.com/microsoft/MSBuildSdks#how-can-i-use-these-sdks
    """
    return struct(
        name = name,
        version = version,
    )

DEFAULT_SDK = MSBuildSdk("Microsoft.NET.Sdk", None)

TfmMappingInfo = provider(
    doc = "Mapping from tfm to canonical name, i.e. netcoreapp3.1 to Microsoft.NetCore.App",
    fields = {
        "dict": "the mapping",
    },
)

FrameworkInfo = provider(
    fields = {
        "tfm": "the target framework moniker (netcoreapp3.1)",
        "implicit_deps": "implicit nuget dependencies of the framework",
    },
)

DotnetSdkInfo = provider(
    doc = "Contains information about the Dotnet SDK used in the toolchain",
    fields = {
        "dotnetos": "The host OS the SDK was built for.",
        "dotnetarch": "The host architecture the SDK was built for.",
        "root_file": "A file in the SDK root directory",
        "runfiles": "Files required to run a command with the sdk",
        "bazel_props": "",
        "sdk_root": ("The versioned root (typically in Sdk/<{version}>/ of the " +
                     "extracted folder"),
        "major_version": "The major version of the sdk",
        "sdk_files": ("The files under sdk_root"),
        "fxr": ("The hstfxr.dll"),
        "shared": ("The shared sdk libraries in a dict from canonical name i.e. Microsoft.NETCore.App"),
        "packs": ("NuGet packages included with the SDK"),
        "tools": ("List of executable files in the SDK built for " +
                  "the execution platform, excluding the dotnet binary file"),
        "dotnet": "The dotnet binary file",
        "all_files": "depset of all sdk files",
        "config": "the dotnet_config.",
    },
)

DotnetConfigInfo = provider(
    doc = "Provider for dotnet_config",
    fields = {
        "nuget_config": "Build-time nuget.config, configures nuget to not fetch any packages on the internet.",
        "trim_path": "path for the builder to trim to bazelify and unbazelify inputs and outputs of msbuild.",
        "tfm_mapping": "The dict from TfmMappingInfo.",
        "test_logger": "The default JUnit compatible test logger to output bazel compatible test logs",
    },
)
