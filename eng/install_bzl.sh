#!/bin/bash
set -e

pkg="dotnet/tools/Bzl"

bazel build "//$pkg:Bzl_nuget"

dotnet tool update -g Bzl --add-source "bazel-bin/$pkg"
