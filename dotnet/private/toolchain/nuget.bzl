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
    group names:
        - compile: files needed at compile time. Folders seen: `ref`, `lib`. I assume `ref` files are reference
            assemblies that are not needed at runtime.
                System.Xml.XDocument/4.3.0 has different `ref` and `runtime` files.
        - runtime: files are often in the `lib` folder, these get copied to the output directory.
            Note: these are not "runfiles", but instead assemblies loaded at runtime i.e. implementation assemblies.
        - build: this group can contain .targets, .props, and other files. These files are used by the project build
            system.

"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    "@my_rules_dotnet//dotnet/private/msbuild:xml.bzl",
    "prepare_nuget_config",
    "prepare_restore_file",
    "project_references",
)
load("@my_rules_dotnet//dotnet/private/actions:common.bzl", "make_dotnet_cmd")
load("@my_rules_dotnet//dotnet/private/toolchain:sdk.bzl", "detect_host_platform")
load("@my_rules_dotnet//dotnet/private:providers.bzl", "DEFAULT_SDK", "MSBuildSdk")

def _nuget_fetch_impl(ctx):
    config = struct(
        intermediate_base = "_obj",
        packages_folder = "packages",
        fetch_config = "NuGet.Fetch.Config",
        packages_by_tfm = {},  # {tfm:package_list} of requested packages
        packages = {},  # {pkg_name/version:package_info} where keys are in all lowercase
        all_files = [],
    )

    _generate_nuget_configs(ctx, config)
    fetch_project = _generate_fetch_project(ctx, config)
    os, _ = detect_host_platform(ctx)

    bin_label = ctx.attr.dotnet_bin

    print(ctx.os.name)
    ext = ".exe" if os == "windows" else ""
    dotnet_path = ctx.path(bin_label.relative(":dotnet" + ext))
    args, env, _ = make_dotnet_cmd(
        str(dotnet_path.dirname),
        os,
        paths.basename(str(fetch_project)),
        "restore",
        True,  # todo(#51) determine when to binlog
    )
    args = [dotnet_path] + args
    ctx.report_progress("Fetching NuGet packages for frameworks: {}".format(", ".join(config.packages_by_tfm.keys())))
    result = ctx.execute(
        args,
        environment = env,
        quiet = False,
        working_directory = str(fetch_project.dirname),
    )
    if result.return_code != 0:
        fail(result.stdout)

    # first we have to collect all the target framework information for each package
    ctx.report_progress("Processing packages")
    _process_assets_json(ctx, config)

    # once we have the full information for each package, we can write the build file for that package
    ctx.report_progress("Generating build files")
    _generate_build_files(ctx, config)

def _generate_nuget_configs(ctx, config):
    substitutions = prepare_nuget_config(
        config.packages_folder,
        True,
        # todo(#46) allow custom package sources
        {"nuget.org": "https://api.nuget.org/v3/index.json"},
    )
    ctx.template(
        ctx.path(config.fetch_config),
        ctx.attr._config_template,
        substitutions = substitutions,
    )

def _generate_fetch_project(ctx, config):
    build_traversal = MSBuildSdk(name = "Microsoft.Build.Traversal", version = "3.0.3")

    _process_packages(ctx, config)

    project_names = []
    for tfm, pkgs in config.packages_by_tfm.items():
        proj_name = tfm + ".proj"
        project_names.append(proj_name)
        substitutions = prepare_restore_file(
            DEFAULT_SDK,
            paths.join(config.intermediate_base, tfm),
            [],
            pkgs.values(),
            config.fetch_config,  # this has to be specified for _every_ project
            tfm,
        )
        ctx.template(
            ctx.path(proj_name),
            ctx.attr._tfm_template,
            substitutions = substitutions,
        )

    substitutions = prepare_restore_file(
        build_traversal,
        paths.join(config.intermediate_base, "traversal"),
        project_references(project_names),
        [],
        config.fetch_config,
        None,  # no tfm for the traversal project
    )
    fetch_project = ctx.path("nuget.fetch.proj")
    ctx.template(
        fetch_project,
        ctx.attr._master_template,
        substitutions = substitutions,
    )
    return fetch_project

def _process_packages(ctx, config):
    seen_names = {}
    for spec, frameworks in ctx.attr.packages.items():
        parts = spec.split(":")
        if len(parts) != 2:
            fail("Invalid version spec, expected `packagename:version-string` got {}".format(spec))

        requested_name = parts[0]
        version_spec = parts[1]
        requested_name_lower = requested_name.lower()
        if requested_name_lower in seen_names:
            # todo(#47)
            fail("Multiple package versions are not supported.")
        seen_names[requested_name_lower] = True

        pkg = struct(
            name = requested_name,
            version = version_spec,
            # todo(#53) don't count on the Version Spec being a precise version
            pkg_id = requested_name_lower + "/" + version_spec.lower(),
            frameworks = {},
            all_files = [],
        )
        config.packages[pkg.pkg_id] = pkg

        for tfm in frameworks:
            tfm_dict = config.packages_by_tfm.setdefault(tfm, {})
            tfm_dict[pkg.name] = pkg

def _get(obj, name):
    value = obj.get(name, None)
    if value == None:
        fail("Missing required json key in project.assets.json, it is likely corrupted: '{}'".format(name))
    return value

def _get_filegroup(desc, name):
    group = desc.pop(name, None)
    if group != None:
        # todo(#48) figure out what to do with the values of this dictionary
        return group.keys()

    # this will be None if the requested group name isn't present in the NuGet package. i.e. not all packages have the
    #   `resources` group.
    return None

def _process_assets_json(ctx, config):
    for tfm, pkg_dict in config.packages_by_tfm.items():
        # reminder: pkg_dict is {pkg_id_lower:struct}
        path = paths.join(config.intermediate_base, tfm, "project.assets.json")
        assets = json.decode(ctx.read(path))

        version = _get(assets, "version")
        if version != 3:  # no idea how often this changes
            fail("Unsupported project.assets.json version: {}.".format(version))

        # dict[pkg_id: Object]
        # sha512
        # type: valid values are [package, project], but package is the only value we will get in this particular usage
        # path: the filepath to the package folder, appears to be pkg_id_lower
        # files: a list of all files contained in the package, the actual .nupkg is not in this list.
        libraries = _get(assets, "libraries")

        # dict[ _tfi_: dict[ filegroup_name: path_dict ]]
        targets = _get(assets, "targets")
        if len(targets) > 1:
            fail("Expected only one Target Framework to be restored in {} but found '{}'".format(
                path,
                "'; '".join(targets.keys()),
            ))
        tfm_pkgs = targets.values()[0]
        for pkg_id, desc in tfm_pkgs.items():
            pkg_id_lower = pkg_id.lower()
            pkg = config.packages.get(pkg_id_lower, None)
            if pkg == None:
                # todo(#52) handle package dependencies
                # todo(#53) support non-precise version specs
                fail("[{}] User unspecified packages are not supported.".format(pkg_id))

            pkg_deps = desc.pop("dependencies", None)
            if pkg_deps != None:
                # todo(#52) handle package dependencies
                fail("[{}] Package dependencies are not supported.".format(pkg_id))

            # list of all files in the package. NuGet needs these to generate downstream project.assets.json files
            # during restore of projects we are actually compiling.
            pkg_files = _get(libraries, pkg_id)["files"]
            pkg.all_files.extend([
                _package_file_path(config, pkg_id, f)
                for f in pkg_files
            ])
            pkg.all_files.append(
                _package_file_path(config, pkg_id, pkg_id_lower.replace("/", ".") + ".nupkg"),
            )

            pkg_filegroups = []
            _accumulate_files(pkg_filegroups, config, desc, pkg_id, "compile")
            _accumulate_files(pkg_filegroups, config, desc, pkg_id, "runtime")

            build = _get_filegroup(desc, "build")
            if build != None:
                # todo(#54)
                fail("[{}] Packages with a `build` filegroup are not supported.".format(pkg_id))

            # resource = _get_filegroup(desc, "resource")  # todo(#48)

            desc.pop("type", None)
            remaining = desc.keys()
            if len(remaining) > 0:
                # todo(#49): support other file groups
                fail("[{}] Unknown filegroups: {}".format(pkg_id, ", ".join(remaining)))

            pkg.frameworks[tfm] = _nuget_file_group(tfm, pkg_filegroups)

def _package_file_path(config, pkg_id, file_path):
    return "//:" + "/".join([config.packages_folder, pkg_id.lower(), file_path])

def _accumulate_files(filegroups_list, config, desc, pkg_id, name):
    """Collect a NuGetFileGroup (see definitions).

    Args:
        desc: dict[pkg_path, dict()] so far, for all file groups other than `resource` the bottom dict is empty
            for `resource` it appears to be a list of locales
    Returns a `_nuget_file_list` fragment for substitution into a BUILD file.
    """
    parsed_files = _get_filegroup(desc, name)
    if parsed_files == None:
        return

    labels = []
    for file in parsed_files:
        label = _package_file_path(config, pkg_id, file)
        labels.append(label)
        config.all_files.append(label)
    filegroups_list.append(_nuget_file_list(name, labels))

def _nuget_file_list(name, files):
    return "{name} = [\n        \"{items}\",\n    ],".format(
        name = name,
        items = "\",\n        \"".join(files),
    )

# this name is confusing
def _nuget_file_group(name, groups):
    format_string = """nuget_filegroup(
    name = "{name}",
    {items}
)
"""
    return format_string.format(
        name = name,
        items = "\n    ".join(groups),
    )

def _generate_build_files(ctx, config):
    for pkg in config.packages.values():
        ctx.template(
            ctx.path(paths.join(pkg.name, "BUILD.bazel")),
            ctx.attr._nuget_import_template,
            substitutions = {
                "{name}": pkg.name,
                "{version}": pkg.version,
                "{frameworks}": "\",\n        \"".join([
                    ":" + tfm
                    for tfm in pkg.frameworks.keys()
                ]),
                "{framework_filegroups}": "\n\n".join(pkg.frameworks.values()),
                "{all_files}": "\",\n        \"".join(pkg.all_files),
            },
        )
    ctx.template(
        ctx.path("BUILD.bazel"),
        ctx.attr._root_template,
        substitutions = {
            "{file_list}": "",
        },
    )

nuget_fetch = repository_rule(
    implementation = _nuget_fetch_impl,
    attrs = {
        "packages": attr.string_list_dict(),
        "dotnet_bin": attr.label(
            default = Label("@dotnet_sdk//:dotnet_bin"),
            executable = True,
            cfg = "exec",
        ),
        "_master_template": attr.label(
            default = Label("@my_rules_dotnet//dotnet/private/msbuild:restore.tpl.proj"),
        ),
        "_tfm_template": attr.label(
            default = Label("@my_rules_dotnet//dotnet/private/msbuild:restore.tpl.proj"),
        ),
        "_config_template": attr.label(
            default = Label("@my_rules_dotnet//dotnet/private/msbuild:NuGet.tpl.config"),
            allow_single_file = True,
        ),
        "_nuget_import_template": attr.label(
            default = Label("@my_rules_dotnet//dotnet/private/toolchain:BUILD.nuget_import.bazel"),
            allow_single_file = True,
        ),
        "_root_template": attr.label(
            default = Label("@my_rules_dotnet//dotnet/private/toolchain:BUILD.nuget.bazel"),
            allow_single_file = True,
        ),
    },
)