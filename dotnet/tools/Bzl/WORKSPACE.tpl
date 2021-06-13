workspace(name = "@@workspace_name@@")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "rules_msbuild",
    sha256 = "9b43abf48c82c8603530b809c047f382f01314bbea5a0322b471292076d0a1d4",
    urls = ["https://github.com/samhowes/rules_msbuild/releases/download/0.0.1/rules_msbuild-0.0.1.tar.gz"],
)
load("@rules_msbuild//dotnet:deps.bzl", "dotnet_register_toolchains", "dotnet_rules_dependencies")

dotnet_rules_dependencies()
# See https://dotnet.microsoft.com/download/dotnet for valid versions
dotnet_register_toolchains(version = "host")

load("@rules_msbuild//dotnet:defs.bzl", "nuget_fetch")
nuget_fetch(
    name = "nuget",
    use_host = True,
    target_frameworks = ["netcoreapp3.1"],
    packages = {},
)

load("@io_bazel_rules_go//go:deps.bzl", "go_register_toolchains", "go_rules_dependencies")
load("@bazel_gazelle//:deps.bzl", "gazelle_dependencies")

go_rules_dependencies()

go_register_toolchains(version = "1.16.2")

gazelle_dependencies()