load("@my_rules_dotnet//dotnet/private/rules:context.bzl", "dotnet_context_data")
load("@bazel_gazelle//:def.bzl", "DEFAULT_LANGUAGES", "gazelle", "gazelle_binary")

# dotnet_context_data collects build options and is depended on by all Dotnet targets.
dotnet_context_data(
    name = "dotnet_context_data",
    visibility = ["//visibility:public"],
)

# gazelle:prefix github.com/samhowes/my_rules_dotnet
gazelle(
    name = "gazelle_repos",
    args = [
        "-from_file=go.mod",
        "-to_macro=go_deps.bzl%go_dependencies",
    ],
    command = "update-repos",
)

GO_ARGS = [
    "-go_naming_convention=import",
]

# for when the dotnet language is broken
gazelle(
    name = "gazelle_go",
    args = GO_ARGS,
)

gazelle(
    name = "gazelle",
    args = [
        "-deps_macro=deps/nuget.bzl%nuget_deps",
    ] + GO_ARGS,
    gazelle = ":gazelle_local",
)

gazelle_binary(
    name = "gazelle_local",
    languages = DEFAULT_LANGUAGES + [
        "//gazelle/dotnet",
    ],
)

gazelle(
    name = "gazelle-dotnet",
    args = [
        "-deps_macro=deps/nuget.bzl%nuget_deps",
    ],
    gazelle = "//gazelle/dotnet:gazelle-dotnet",
)
