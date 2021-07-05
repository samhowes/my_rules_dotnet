# credit to https://github.com/bazelbuild/rules_nodejs/blob/stable/internal/common/windows_utils.bzl
BATCH_HEADER = r"""@echo off
SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION
rem Usage of rlocation function:
rem        call :rlocation <runfile_path> <abs_path>
rem        The rlocation function maps the given <runfile_path> to its absolute
rem        path and stores the result in a variable named <abs_path>.
rem        This function fails if the <runfile_path> doesn't exist in mainifest
rem        file.
:: Start of rlocation
goto :rlocation_end
:rlocation
if "%~2" equ "" (
  echo>&2 ERROR: Expected two arguments for rlocation function.
  exit 1
)
if "%RUNFILES_MANIFEST_ONLY%" neq "1" (
  set %~2=%~1
  exit /b 0
)
if exist "%RUNFILES_DIR%" (
  set RUNFILES_MANIFEST_FILE=%RUNFILES_DIR%_manifest
)
if "%RUNFILES_MANIFEST_FILE%" equ "" (
  set RUNFILES_MANIFEST_FILE=%~f0.runfiles\MANIFEST
)
if not exist "%RUNFILES_MANIFEST_FILE%" (
  set RUNFILES_MANIFEST_FILE=%~f0.runfiles_manifest
)
set MF=%RUNFILES_MANIFEST_FILE:/=\%
if not exist "%MF%" (
  echo>&2 ERROR: Manifest file %MF% does not exist.
  exit 1
)
set runfile_path=%~1
for /F "tokens=2* usebackq" %%i in (`%SYSTEMROOT%\system32\findstr.exe /l /c:"!runfile_path! " "%MF%"`) do (
  set abs_path=%%i
)
if "!abs_path!" equ "" (
  echo>&2 ERROR: !runfile_path! not found in runfiles manifest
  exit 1
)
set %~2=!abs_path!
exit /b 0
:rlocation_end
:: End of rlocation
"""

BASH_HEADER = """#!/usr/bin/env bash
# --- begin runfiles.bash initialization v2 ---
# Copy-pasted from the Bazel Bash runfiles library v2.
set -uo pipefail; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
source "$0.runfiles/$f" 2>/dev/null || \\
source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
{ echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v2 ---
"""

def is_windows(ctx):
    """
    Check if we are building for Windows.
    """

    # Only on Windows the path separator would be ';'
    return ctx.configuration.host_path_separator == ";"

def launch_script(ctx, windows, unix):
    executable = None
    if is_windows(ctx):
        launcher_content = BATCH_HEADER + windows
        executable = ctx.actions.declare_file(ctx.attr.name + ".bat")
    else:
        launcher_content = BASH_HEADER + unix
        executable = ctx.actions.declare_file(ctx.attr.name + ".sh")

    # Test executable is a shell script on Linux and macOS and a Batch script on Windows
    ctx.actions.write(
        output = executable,
        is_executable = True,
        content = launcher_content,
    )
    return executable
