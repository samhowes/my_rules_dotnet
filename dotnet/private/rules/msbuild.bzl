load("//dotnet/private:providers.bzl", "DotnetLibraryInfo", "DotnetRestoreInfo", "NuGetPackageInfo")
load("//dotnet/private:context.bzl", "dotnet_context", "dotnet_exec_context")
load("//dotnet/private/actions:restore.bzl", "restore")
load("@bazel_skylib//lib:dicts.bzl", "dicts")

def _publish_impl(ctx):
    pass

def _restore_impl(ctx):
    dotnet = dotnet_exec_context(ctx, False)
    restore_info, outputs = restore(ctx, dotnet)
    return [
        DefaultInfo(
            files = depset([restore_info.intermediate_dir]),
        ),
        restore_info,
        OutputGroupInfo(
            all = depset(outputs),
        ),
    ]

def _binary_impl(ctx):
    pass

def _library_impl(ctx):
    pass

def _test_impl(ctx):
    pass

_TOOLCHAINS = ["@my_rules_dotnet//dotnet:toolchain"]
_COMMON_ATTRS = {
    "project_file": attr.label(allow_single_file = True, mandatory = True),
}

msbuild_publish = rule(
    _publish_impl,
    attrs = dicts.add(_COMMON_ATTRS, {
        "target": attr.label(mandatory = True, providers = [DotnetLibraryInfo]),
    }),
    executable = False,
    toolchains = _TOOLCHAINS,
)

_RESTORE_ATTRS = dicts.add(_COMMON_ATTRS, {
    "target_framework": attr.string(mandatory = True),
    "deps": attr.label_list(providers = [DotnetRestoreInfo]),
})

msbuild_restore = rule(
    _restore_impl,
    attrs = _RESTORE_ATTRS,
    executable = False,
    toolchains = _TOOLCHAINS,
)

_ASSEMBLY_ATTRS = dicts.add(_RESTORE_ATTRS, {
    "srcs": attr.label_list(allow_files = [".cs"]),
    "restore": attr.label(mandatory = True, providers = [DotnetRestoreInfo]),
    "data": attr.label_list(allow_files = True),
    "deps": attr.label_list(providers = [
        [DotnetLibraryInfo],
        [NuGetPackageInfo],
    ]),
})

msbuild_binary = rule(
    _binary_impl,
    attrs = _ASSEMBLY_ATTRS,
    executable = True,
    toolchains = _TOOLCHAINS,
)

msbuild_library = rule(
    _library_impl,
    attrs = _ASSEMBLY_ATTRS,
    executable = False,
    toolchains = _TOOLCHAINS,
)

msbuild_test = rule(
    _test_impl,
    attrs = _ASSEMBLY_ATTRS,
    executable = True,
    test = True,
    toolchains = _TOOLCHAINS,
)
