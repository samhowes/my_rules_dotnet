load(":xml_util.bzl", "inline_element")

NUGET_BUILD_CONFIG = "NuGet.Build.Config"

def prepare_nuget_config(packages_folder, restore_enabled, package_sources):
    sources = []
    for source in package_sources:
        sources.append(inline_element("add", source))

    return {
        "{packages_folder}": packages_folder,
        "{restore_enabled}": str(restore_enabled),
        "{package_sources}": "\n    ".join(sources),
    }
