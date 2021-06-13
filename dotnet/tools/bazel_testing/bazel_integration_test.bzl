load("//dotnet/tools/launcher:launch.bzl", "launch_script", "to_manifest_path")
load("@bazel_skylib//lib:paths.bzl", "paths")

def _rules_msbuild_integration_test_impl(ctx):
    if len(ctx.files.workspace_files) == 0:
        fail("no workspace files, do you need to run `eng/update_deleted.sh`?")

    bazel = None
    for b in ctx.files.bazel_binary:
        if b.basename.find("-") >= 0:
            continue
        bazel = b
        break

    config = ctx.actions.declare_file("%s.config.json" % ctx.attr.name)
    ctx.actions.write(
        output = config,
        content = json.encode(dict(
            workspaceRoot = paths.join(
                ctx.workspace_name,
                paths.dirname(ctx.build_file_path),
                ctx.attr.name.split("_", 1)[1],
            ),
            releaseTar = to_manifest_path(ctx, ctx.file.release),
            bazel = to_manifest_path(ctx, bazel),
        )),
    )
    test_runner = to_manifest_path(ctx, ctx.executable._test_runner)
    args = to_manifest_path(ctx, config)

    executable = launch_script(
        ctx,
        r"""
call :rlocation {TMPL_test_runner} TEST_RUNNER
call :rlocation {TMPL_args} ARGS
%TEST_RUNNER% %ARGS% %*
        """.format(
            TMPL_test_runner = test_runner,
            TMPL_args = args,
        ),
        """
readonly TEST_RUNNER=$(rlocation "{TMPL_test_runner}")
readonly ARGS=$(rlocation "{TMPL_args}")

readonly COMMAND="${{TEST_RUNNER}} ${{ARGS}} $@"
${{COMMAND}}
""".format(
            TMPL_test_runner = test_runner,
            TMPL_args = args,
        ),
    )

    runfiles = ([config, ctx.file.release] +
                ctx.files.bazel_binary +
                ctx.files.workspace_files)
    return [DefaultInfo(
        runfiles = ctx.runfiles(files = runfiles).merge(ctx.attr._test_runner[DefaultInfo].data_runfiles),
        executable = executable,
    )]

rules_msbuild_integration_test = rule(
    implementation = _rules_msbuild_integration_test_impl,
    attrs = {
        "workspace_files": attr.label(
            doc = "A filegroup of all files in the workspace-under-test",
            allow_files = True,
        ),
        "release": attr.label(allow_single_file = True),
        "bazel_binary": attr.label(mandatory = True, allow_files = True),
        "_test_runner": attr.label(
            executable = True,
            cfg = "host",
            default = Label("@rules_msbuild//dotnet/tools/bazel_testing:TestRunner"),
        ),
    },
    test = True,
)
