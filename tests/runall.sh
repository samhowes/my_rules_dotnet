#!/usr/bin/env bash

set -e

bazel_args="${BAZEL_ARGS:-}"
if [[ "$bazel_args" == " " ]]; then
  # azure pipelines doesn't like empty strings as parameters
  bazel_args=""
fi

export MSYS2_ARG_CONV_EXCL="*"

# if these don't build, nothing will
bazel build $bazel_args //tests/sanity //tests/examples/HelloBazel

bazel test $bazel_args //... --test_tag_filters=-e2e

bazel run $bazel_args //:gazelle-dotnet

# these should all be cached because gazelle dotnet shouldn't change anything
# even if they aren't fully cached, they should still pass
bazel test $bazel_args //... --test_tag_filters=-e2e

# targets that __must__ be run by themselves
bazel build $bazel_args //tests/sandboxing/parallel

bazel --host_jvm_args=-Xms256m --host_jvm_args=-Xmx1280m test --test_tag_filters=e2e --local_ram_resources=792 $bazel_args //...
