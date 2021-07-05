package main

import (
	"github.com/samhowes/rules_msbuild/tests/tools/executable"
	"github.com/samhowes/rules_msbuild/tests/tools/files"
	"github.com/stretchr/testify/assert"
	"io/ioutil"
	"testing"
)

const expected = "Hello Runfiles!\n"

func TestRunGenrule(t *testing.T) {
	p, _ := files.Path("run_dotnet_cat_result.txt")
	contentBytes, err := ioutil.ReadFile(p)
	if err != nil {
		t.Fatalf("failed to read genrule result: %v", err)
	}

	assert.Equal(t, expected, files.EndingsB(contentBytes))
}

func TestRunDataDep(t *testing.T) {
	p, _ := files.BinPath("DotnetCat")
	config := lib.TestConfig{
		ExpectedOutput: expected,
		Target:         p,
	}
	lib.CheckExecutableOutput(t, &config)
}
