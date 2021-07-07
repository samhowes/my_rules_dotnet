"""
Definitions: (some are made up)
- Canonical Name: The PascalCase name of the package as it would be displayed on a web page, i.e. `CommandLineParser`
- Requested Name: The name that the user listed as part of the key of the dictionary passed to `nuget_fetch`
    this can be the Canonical Name with _any casing_ i.e. `ComManDlIneParser`
- Version String: A specific NuGet version string i.e. `2.9.0-preview1`
- Version Spec: A string that can be resolved to a Version String by NuGet that is entered by the user as the second
    half of the key to the dictionary passed to nuget_fetch. i.e. `2.9.*`. Currently, only precise version specs are
    supported. i.e. `2.9.0`.
    Other examples: `[2.4.1]`
- Package Id (pkg_id): CanonicalName/VersionString i.e. `CommandLineParser/2.9.0-preview1`
- Package Id Lower (pkg_id_lower): canonicalname/versionstring i.e. `commandlineparser/2.9.0-preview1`
- Target Framework Moniker (tfm): An identifier used to indicate the target framework in a .csproj file and in a build
    output folder i.e. `netcoreapp3.1`. The user is likely familiar with this string. It is well documented.
- Target Framework Identifier (tfi): An identifier used to indicate the target framework in some rare cases in the build
    process by NuGet and maybe MSBuild. i.e. `.NETCoreApp,Version=v3.1` It is not well documented.
- NuGet File Group: A grouping of files in a NuGet package. The group name, i.e. `compile` or `runtime` indicates what
    phase of the build the files are used in.
    https://docs.microsoft.com/en-us/nuget/create-packages/creating-a-package#from-a-convention-based-working-directory
    Background on reference assemblies vs implementation assemblies:
    https://github.com/dotnet/standard/blob/master/docs/history/evolution-of-design-time-assemblies.md
    group names:
        - compile: files needed at compile time. Folders seen: `ref`, `lib`. I assume `ref` files are reference
            assemblies that are not needed at runtime.
                System.Xml.XDocument/4.3.0 has different `ref` and `runtime` files.
        - runtime: files are often in the `lib` folder, these get copied to the output directory.
            Note: these are not "runfiles", but instead assemblies loaded at runtime i.e. implementation assemblies.
        - build: this group can contain .targets, .props, and other files. These files are used by the project build
            system.
        - runtimeTargets: files for specific runtimes that are being targeted. Items in this group are identified by
            runtimes/<rid>/<group>/<tfm>/Package.Name.dll. Tfm in this case is the tfm of the package that supports
            the tfm being built. i.e. if netcoreapp3.1 is being built, then tfm could refer to netstandard1.6.
            Example file references:
                runtimes/opensuse.42.1-x64/native/System.Security.Cryptography.Native.OpenSsl.so
                runtimes/osx.10.10-x64/native/System.Security.Cryptography.Native.Apple.dylib
        - resource: appears to be resource dlls for different locales. The value of the dictionary is a dictionary of
            locales supported.

"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    "//dotnet/private/msbuild:xml.bzl",
    "STARTUP_DIR",
    "prepare_project_file",
)
load("//dotnet/private/msbuild:nuget.bzl", "NUGET_BUILD_CONFIG", "prepare_nuget_config")
load("//dotnet/private/toolchain:common.bzl", "BUILDER_PACKAGES", "default_tfm", "detect_host_platform")
load("//dotnet/private:providers.bzl", "DEFAULT_SDK", "MSBuildSdk")
load("//dotnet/private:context.bzl", "dotnet_context", "make_cmd")

_TfmInfo = provider(fields = ["tfn", "implicit_deps"])

def _nuget_fetch_impl(ctx):
    config = struct(
        fetch_base = ctx.path("fetch"),
        parser_base = ctx.path("fetch/parser"),
        intermediate_base = ctx.path("fetch/_obj"),
        packages_folder = "packages",
        fetch_config = ctx.path("NuGet.Fetch.Config"),
        packages_by_tfm = {},  # dict[tfm, dict[pkg_id_lower: _pkg]] of requested packages
        packages = {},  # {pkg_name/version: _pkg} where keys are in all lowercase
    )
    os, _ = detect_host_platform(ctx)
    dotnet = dotnet_context(
        str(ctx.path(ctx.attr.dotnet_sdk_root).dirname),
        os,
    )

    _configure_host_packages(ctx, dotnet, config)

    _generate_nuget_configs(ctx, config)
    parser_project = _copy_parser(ctx, config)
    fetch_project, tfm_projects = _generate_fetch_project(ctx, config, parser_project)

    args = make_cmd(paths.basename(str(fetch_project)), "restore")
    args = [dotnet.path] + args + ["-p:BazelFetch=true"]
    ctx.report_progress("Fetching NuGet packages for frameworks: {}".format(", ".join(config.packages_by_tfm.keys())))
    result = ctx.execute(
        args,
        environment = dotnet.env,
        quiet = False,
        working_directory = str(fetch_project.dirname),
    )
    if result.return_code != 0:
        fail("failed executing '{}': {}".format(" ".join(args), result.stdout))

    # first we have to collect all the target framework information for each package
    ctx.report_progress("Generating build files")
    _process_assets_json(ctx, dotnet, config, parser_project, tfm_projects)

def _configure_host_packages(ctx, dotnet, config):
    if not ctx.attr.use_host:
        return

    # https://docs.microsoft.com/en-us/dotnet/core/tools/dotnet-nuget-locals
    cache_type = "global-packages"
    args = [
        dotnet.path,
        "nuget",
        "locals",
        cache_type,
        "--list",
    ]

    result = ctx.execute(args)
    if result.return_code != 0:
        fail("failed to find global-packages folder with dotnet: " + result.stderr)

    # example dotnet5 output: `global-packages: /Users/samh/.nuget/packages/`
    # example dotnet3.1 output: `info : global-packages: /Users/samh/.nuget/packages/`
    ind = result.stdout.index(cache_type)
    if ind < 0:
        fail("unexpected output from {}: {}".format(" ".join(args), result.stdout))
    start = ind + len(cache_type) + 2
    location = result.stdout[start:].strip()

    # it's possible that the packages folder doesn't exist yet, if it doesn't the symlink won't be functional
    # this mostly likely won't be the case in actual usage, but is definitely possible if the folder has been
    # cleaned, like on a fresh CI instance for example.
    mkdir = None
    if dotnet.os == "windows":
        mkdir = ["cmd", "/e:on", "/c", "mkdir " + location]
    else:
        mkdir = ["mkdir", "-p", location]

    ctx.execute(mkdir)
    ctx.symlink(location, config.packages_folder)

def _copy_parser(ctx, config):
    parser_path = ctx.path(ctx.attr._parser_project)
    for f in parser_path.dirname.readdir():
        if f.basename in {"bin": True, "obj": True}:
            continue
        contents = ctx.read(f)
        ctx.file(config.parser_base.get_child(f.basename), contents, legacy_utf8 = False)

    return config.parser_base.get_child(parser_path.basename)

def _pkg(name, version, pkg_id = None):
    name_lower = name.lower()
    version_lower = version.lower()
    if pkg_id == None:
        pkg_id = name_lower + "/" + version_lower

    return struct(
        name = name,
        name_lower = name_lower,
        # this field has to be compatible with the NuGetPackageInfo struct
        version = version,
        label = "//{}".format(name),
        pkg_id = pkg_id,
        frameworks = {},  # dict[tfm: string] string is a filegroup to be written into a build file
        all_files = [],  # list[str]
        deps = {},  # dict[tfm: list[pkg]]
        filegroups = {},  # dict[tfm: list[string]]
    )

def _generate_nuget_configs(ctx, config):
    substitutions = prepare_nuget_config(
        config.packages_folder,
        True,
        # todo(#46) allow custom package sources
        [
            {"key": "SamHowes", "value": "/Users/samh/dev/msbuild/artifacts/packages/Debug/Shipping"},
            {"key": "nuget.org", "value": "https://api.nuget.org/v3/index.json", "protocolVersion": "3"},
        ],
    )
    ctx.template(
        ctx.path(config.fetch_config),
        ctx.attr._config_template,
        substitutions = substitutions,
    )

    substitutions = prepare_nuget_config(
        config.packages_folder,
        False,  # no fetch allowed at build time
        [],  # don't even add sources, just in case
    )
    ctx.template(
        ctx.path(NUGET_BUILD_CONFIG),
        Label("@rules_msbuild//dotnet/private/msbuild:NuGet.tpl.config"),
        executable = False,
        substitutions = substitutions,
    )

def _generate_fetch_project(ctx, config, parser_project):
    build_traversal = MSBuildSdk(name = "Microsoft.Build.Traversal", version = "3.0.3")

    _process_packages(ctx, config)

    tfm_projects = []
    for tfm, pkgs in config.packages_by_tfm.items():
        proj = config.fetch_base.get_child(tfm + ".proj")
        tfm_projects.append(proj)
        substitutions = prepare_project_file(
            DEFAULT_SDK,
            paths.join(str(config.intermediate_base.basename), tfm),
            [],
            pkgs.values(),
            config.fetch_config,  # this has to be specified for _every_ project
            tfm,
            exec_root = STARTUP_DIR,
        )
        ctx.template(
            proj,
            ctx.attr._tfm_template,
            substitutions = substitutions,
        )

    substitutions = prepare_project_file(
        build_traversal,
        paths.join(str(config.intermediate_base.basename), "traversal"),
        [p.basename for p in tfm_projects] + [str(parser_project)],
        [],
        config.fetch_config,
        None,  # no tfm for the traversal project
        exec_root = STARTUP_DIR,
    )
    fetch_project = config.fetch_base.get_child("nuget.fetch.proj")
    ctx.template(
        fetch_project,
        ctx.attr._master_template,
        substitutions = substitutions,
    )
    return fetch_project, tfm_projects

def _process_packages(ctx, config):
    seen_names = {}
    sdk_version = ctx.path(ctx.attr.dotnet_sdk_root).dirname.get_child("sdk").readdir()[-1]

    tfm = default_tfm(sdk_version.basename)
    for pkg_name, version in ctx.attr.builder_deps.items():
        _record_package(config, seen_names, pkg_name, version, [tfm], True)

    for tfm in ctx.attr.target_frameworks + [tfm]:
        config.packages_by_tfm.setdefault(tfm, {})

    for spec, frameworks in ctx.attr.packages.items():
        parts = spec.split(":")
        if len(parts) != 2:
            fail("Invalid version spec, expected `packagename:version-string` got {}".format(spec))

        requested_name = parts[0]
        version_spec = parts[1]

        _record_package(config, seen_names, requested_name, version_spec, frameworks)

    pkg_name, version, tfm = ctx.attr.test_logger.split(":")
    _record_package(config, seen_names, pkg_name, version, ctx.attr.target_frameworks)

def _record_package(config, seen_names, requested_name, version_spec, frameworks, use_existing = False):
    # todo(#53) don't count on the Version Spec being a precise version
    pkg = _pkg(requested_name, version_spec)

    if pkg.name_lower in seen_names and not use_existing:
        # todo(#47)
        fail("Found multiple versions of package {}. Multiple package versions are not supported.".format(pkg.name_lower))
    if not use_existing:
        seen_names[pkg.name_lower] = True

    config.packages[pkg.pkg_id] = pkg

    for tfm in frameworks:
        tfm_dict = config.packages_by_tfm.setdefault(tfm, {})
        if not use_existing or pkg.name_lower not in tfm_dict:
            tfm_dict[pkg.name_lower] = pkg

def _process_assets_json(ctx, dotnet, config, parser_project, tfm_projects):
    args = [
        dotnet.path,
        "build",
        "-p:BazelFetch=true",
        "-p:OutputPath=bin",
        "-p:AppendTargetFrameworkToOutputPath=false",
        "--no-restore",
        str(parser_project),
    ]

    result = ctx.execute(
        args,
        environment = dotnet.env,
        working_directory = str(parser_project.dirname),
    )
    if result.return_code != 0:
        fail("failed to build nuget parser, please file an issue.\nstdout: {}\nstderr: {}".format(result.stdout, result.stderr))

    args = [
        dotnet.path,
        "exec",
        paths.join(str(parser_project.dirname), "bin", paths.split_extension(parser_project.basename)[0] + ".dll"),
        "-dotnet_path",
        dotnet.path,
        "-intermediate_base",
        str(config.intermediate_base),
        "-packages_folder",
        str(ctx.path(config.packages_folder)),
        "-test_logger",
        ctx.attr.test_logger.split(":")[0],
        "-nuget_build_config",
        NUGET_BUILD_CONFIG,
    ]
    args.extend([str(p) for p in tfm_projects])

    result = ctx.execute(args, quiet = True, environment = dotnet.env)
    if result.return_code != 0:
        fail("failed to process restored packages, please file an issue.\nexit code: {}\nstdout: {}\nstderr: {}".format(result.return_code, "foo" + result.stdout + "bar", "what" + result.stderr + "how"))

nuget_fetch = repository_rule(
    implementation = _nuget_fetch_impl,
    attrs = {
        "packages": attr.string_list_dict(),
        "test_logger": attr.string(
            default = "JunitXml.TestLogger:3.0.87:netstandard2.0",
        ),
        "builder_deps": attr.string_dict(
            default = BUILDER_PACKAGES,
        ),
        # todo(#63) link this to the primary nuget folder if it is not the primary nuget folder
        "dotnet_sdk_root": attr.label(
            default = Label("@dotnet_sdk//:ROOT"),
        ),
        "use_host": attr.bool(
            default = False,
            doc = ("When false (default) nuget packages will be fetched into a bazel-only directory, when true, the " +
                   "host machine's global packages folder will be used. This is determined by executing " +
                   "`dotnet nuget locals global-packages --list"),
        ),
        "target_frameworks": attr.string_list(mandatory = True),
        "_master_template": attr.label(
            default = Label("@rules_msbuild//dotnet/private/msbuild:project.tpl.proj"),
        ),
        "_tfm_template": attr.label(
            default = Label("@rules_msbuild//dotnet/private/msbuild:project.tpl.proj"),
        ),
        "_config_template": attr.label(
            default = Label("@rules_msbuild//dotnet/private/msbuild:NuGet.tpl.config"),
            allow_single_file = True,
        ),
        "_nuget_import_template": attr.label(
            default = Label("@rules_msbuild//dotnet/private/toolchain:BUILD.nuget_import.bazel"),
            allow_single_file = True,
        ),
        "_root_template": attr.label(
            default = Label("@rules_msbuild//dotnet/private/toolchain:BUILD.nuget.bazel"),
            allow_single_file = True,
        ),
        "_parser_project": attr.label(
            default = Label("@rules_msbuild//dotnet/tools/NuGetParser:NuGetParser.csproj"),
        ),
        "_parser_srcs": attr.label(
            default = Label("@rules_msbuild//dotnet/tools/NuGetParser:NuGetParser_srcs"),
        ),
    },
)
