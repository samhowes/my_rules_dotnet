package main

import (
	"github.com/samhowes/rules_msbuild/tests/tools/executable"
	"github.com/samhowes/rules_msbuild/tests/tools/files"
	"path"
	"testing"
)

func TestRunPublishOutput(t *testing.T) {

	publishDir, err := files.Path("publish/netcoreapp3.1")
	if err != nil {
		t.Fatalf("can't locate publish directory: %v", err)
	}
	assemblyPath := path.Join(publishDir, "HelloWeb.dll")

	lib.CheckDotnetOutput(t, assemblyPath, "The special value is: 42!\n")
}
