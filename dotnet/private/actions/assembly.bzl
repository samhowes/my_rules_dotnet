load("//dotnet/private:providers.bzl", "DotnetLibraryInfo", "DotnetRestoreInfo")
load("//dotnet/private:context.bzl", "make_builder_cmd")
load(":common.bzl", "declare_cache", "get_nuget_files", "write_cache_manifest")
load("@bazel_skylib//lib:paths.bzl", "paths")

def build_assembly(ctx, dotnet):
    restore = ctx.attr.restore[DotnetRestoreInfo]

    output_dir = ctx.actions.declare_directory(dotnet.config.output_dir_name)
    assembly = ctx.actions.declare_file(paths.join(output_dir.basename, ctx.attr.name + ".dll"))

    intermediate_dir = ctx.actions.declare_directory(paths.join("obj", dotnet.config.tfm))

    # we don't need this file, but adding will make sure bazel fails the build if it isn't created because msbuild
    # didn't listen to our paths
    intermediate_assembly = ctx.actions.declare_file(paths.join("obj", dotnet.config.tfm, assembly.basename))

    build_cache = declare_cache(ctx)

    dep_files, input_caches, runfiles = _process_deps(ctx, dotnet, restore)
    cache_manifest = write_cache_manifest(ctx, input_caches)
    args, cmd_outputs = make_builder_cmd(ctx, dotnet, "build")

    inputs = depset(
        [cache_manifest],
        transitive = [dep_files, dotnet.sdk.runfiles],
    )

    outputs = [output_dir, assembly, intermediate_dir, intermediate_assembly, build_cache] + cmd_outputs

    ctx.actions.run(
        mnemonic = "MSBuild",
        inputs = inputs,
        outputs = outputs,
        executable = dotnet.sdk.dotnet,
        arguments = [args],
        env = dotnet.env,
        tools = dotnet.builder.files,
    )

    info = DotnetLibraryInfo(
        assembly = assembly,
        output_dir = output_dir,
        # set runfiles here so we can use it in the publish action without including the dotnet sdk
        runfiles = runfiles,
        intermediate_dir = intermediate_dir,
        build_cache = build_cache,
        build_caches = depset(
            [build_cache],
            transitive = [input_caches],
        ),
        dep_files = dep_files,
        restore = restore,
    )

    return info, outputs

def _process_deps(ctx, dotnet, restore_info):
    files = [
        restore_info.project_file,
        restore_info.restore_dir,
        restore_info.cache,
    ] + (ctx.files.msbuild_directory +
         # include and content because msbuild could copy them to the output directory of any dependent assembly
         ctx.files.srcs +
         ctx.files.content)
    caches = []
    runfiles = []

    # we need the full transitive closure of dependency files here because MSBuild
    # could decide to copy some of these files to the output directory
    # this will definitely happen for an exe build, and may happen for other assemblies
    # depending on the user's project settings
    transitive = [restore_info.dep_files]

    for d in dotnet.config.implicit_deps:
        get_nuget_files(d, dotnet.config.tfm, transitive)

    for d in ctx.attr.deps:
        if DotnetLibraryInfo in d:
            info = d[DotnetLibraryInfo]
            files.extend([
                info.output_dir,
                info.build_cache,
            ])
            transitive.append(info.dep_files)
            caches.append(info.build_caches)
            runfiles.append(info.runfiles)

    return (
        depset(files, transitive = transitive),
        depset([restore_info.cache], transitive = caches),
        depset(ctx.files.data, transitive = runfiles),
    )
