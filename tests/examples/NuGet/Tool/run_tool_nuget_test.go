package main

import (
	"archive/zip"
	"bufio"
	"github.com/bazelbuild/rules_go/go/tools/bazel"
	lib "github.com/samhowes/rules_msbuild/tests/tools/executable"
	"io"
	"os"
	"path"

	"github.com/samhowes/rules_msbuild/tests/tools/files"
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestToolPackageContents(t *testing.T) {
	nupkgPath, err := files.Path("Tool.1.2.3.nupkg")
	assert.NoError(t, err)
	r, err := zip.OpenReader(nupkgPath)

	assert.NoError(t, err)
	defer r.Close()

	tmp, err := bazel.NewTmpDir("tool")
	assert.NoError(t, err)

	fmap := map[string]*zip.File{}
	for _, f := range r.File {
		fmap[f.Name] = f
		destPath := path.Join(tmp, f.Name)
		t.Logf(f.Name)
		err = os.MkdirAll(path.Dir(destPath), os.ModePerm)
		assert.NoError(t, err)

		dest, err := os.Create(destPath)

		assert.NoError(t, err)
		rc, err := f.Open()
		assert.NoError(t, err)

		w := bufio.NewWriter(dest)
		_, err = io.Copy(w, rc)
		assert.NoError(t, err)
		err = dest.Close()
		assert.NoError(t, err)
	}
	assertExists := func(p string) string {
		fullP := path.Join(tmp, p)
		_, err = os.Stat(fullP)
		assert.NoError(t, err, "expected %s to exist", p)
		return fullP
	}

	_ = assertExists("content/runfiles/rules_msbuild/tests/examples/NuGet/Tool/foo.txt")
	dll := assertExists("tools/netcoreapp3.1/any/Tool.dll")

	lib.CheckDotnetOutput(t, dll, "runfile contents: bar\n\n")

}

//func TestRunPublishOutput(t *testing.T) {
//	dotnetPath := files.BinPath("@dotnet")
//	publishDir := files.Path("publish/netcoreapp3.1")
//	if publishDir == "" {
//		t.Fatalf("can't locate publish directory")
//	}
//	assemblyPath := path.Join(publishDir, "HelloWeb.dll")
//
//	config := lib.TestConfig{
//		Args:           []string{assemblyPath},
//		ExpectedOutput: "The special value is: 42!\n",
//		Target:         dotnetPath,
//	}
//	os.Setenv("DOTNET_CLI_HOME", path.Dir(dotnetPath))
//	os.Setenv("DOTNET_SKIP_FIRST_TIME_EXPERIENCE", "1")
//	os.Setenv("DOTNET_MULTILEVEL_LOOKUP", "0")
//	os.Setenv("DOTNET_NOLOGO", "0")
//	t.Logf("dotnet path: %s\n", config.Target)
//	lib.CheckExecutableOutput(t, &config)
//}
