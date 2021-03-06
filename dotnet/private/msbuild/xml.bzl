"""Xml Helpers"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:providers.bzl", "MSBuildSdk")
load(":xml_util.bzl", "inline_element")

INTERMEDIATE_BASE = "obj"
STARTUP_DIR = "$(MSBuildStartupDirectory)"
EXEC_ROOT = "$(ExecRoot)"
THIS_DIR = "$(MSBuildThisFileDirectory)"

def properties(property_dict):
    return "\n    ".join([
        element(k, v)
        for k, v in property_dict.items()
    ])

def element(name, value, attrs = {}):
    open_tag_items = [name]
    open_tag_items.extend(
        [
            '{}="{}"'.format(k, v)
            for k, v in attrs.items()
        ],
    )
    return "<{open_tag}>{value}</{name}>".format(
        name = name,
        open_tag = " ".join(open_tag_items),
        value = value,
    )

def _import_sdk(name, project_type, version = None):
    attrs = {
        "Project": "Sdk." + project_type,
        "Sdk": name,
    }
    if version != None:
        attrs["Version"] = version
    return inline_element("Import", attrs)

def import_sdk(name, version = None):
    return (
        _import_sdk(name, "props", version),
        _import_sdk(name, "targets", version),
    )

def prepare_project_file(
        msbuild_sdk,
        intermediate_path,
        references,
        packages,
        nuget_config_path,
        tfm = None,
        pre_sdk_properties = {},
        post_sdk_properties = {},
        srcs = [],
        imports = [],
        exec_root = EXEC_ROOT):
    pre_import_msbuild_properties = dicts.add(pre_sdk_properties, {
        "RestoreConfigFile": nuget_config_path,
        # this is where nuget creates project.assets.json (and other files) during a restore
        "BaseIntermediateOutputPath": THIS_DIR + intermediate_path,
        "IntermediateOutputPath": paths.join(THIS_DIR, intermediate_path),
        # https://docs.microsoft.com/en-us/visualstudio/msbuild/customize-your-build?view=vs-2019#msbuildprojectextensionspath
        # this is where nuget looks for a project.assets.json during a build
        "MSBuildProjectExtensionsPath": THIS_DIR + intermediate_path,
        # we could just set ProjectAssetsFile here, but we're setting the other properties in case they have other impacts
        "OutputPath": THIS_DIR + paths.dirname(intermediate_path),
        #"ImportDirectoryBuildProps": "false",
        "UseSharedCompilation": "false",
    })

    post_import_msbuild_properties = dicts.add(post_sdk_properties, {})

    if tfm != None:
        post_import_msbuild_properties["TargetFramework"] = tfm

    compile_srcs = [
        inline_element("Compile", {"Include": paths.join(exec_root, src.path)})
        for src in srcs
    ]

    project_references = [
        inline_element("ProjectReference", {"Include": path})
        for path in references
    ]

    package_references = [
        inline_element(
            "PackageReference",
            {
                "Include": p.name,
                "Version": p.version,
            },
        )
        for p in packages
    ]

    props, targets = [], []
    if msbuild_sdk != None:
        p, t = import_sdk(msbuild_sdk.name, msbuild_sdk.version)
        props.append(p)
        targets.append(t)
    else:
        props = [inline_element("Import", {"Project": paths.join(exec_root, i.path)}) for i in imports]

    sep = "\n    "
    substitutions = {
        "{pre_import_msbuild_properties}": properties(pre_import_msbuild_properties),
        "{sdk_props}": sep.join(props),
        "{post_import_msbuild_properties}": properties(post_import_msbuild_properties),
        "{compile_srcs}": sep.join(compile_srcs),
        "{references}": sep.join(project_references),
        "{package_references}": sep.join(package_references),
        "{sdk_targets}": sep.join(targets),
    }

    return substitutions
