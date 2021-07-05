package main

import (
	"fmt"
	"github.com/samhowes/rules_msbuild/tests/tools/executable"
	"github.com/samhowes/rules_msbuild/tests/tools/files"
	"github.com/stretchr/testify/assert"
	"io/ioutil"
	"os"
	"path"
	"runtime"
	"strings"
	"testing"
)

const GREETER = "Greeter"

func TestRunGenrule(t *testing.T) {
	es := os.Environ()
	for _, e := range es {
		fmt.Println(e)
	}

	p, _ := files.Path("run_greeter.txt")
	contentBytes, err := ioutil.ReadFile(p)
	if err != nil {
		t.Fatalf("failed to read genrule result: %v", err)
	}
	actual := files.Endings(string(contentBytes))
	assert.Equal(t, "Hello: genrule!\n", actual)
}

func greeterName() string {
	return files.BinName("Greeter")
}

func TestRunDataDep(t *testing.T) {
	binPath, _ := files.BinPath(GREETER)
	config := lib.TestConfig{
		Args:           []string{"data dep"},
		ExpectedOutput: "Hello: data dep!\n",
		Target:         binPath,
	}
	lib.CheckExecutableOutput(t, &config)
}

// Simulate the user executing the binary directly given that they have built it directly
func TestRunDirect(t *testing.T) {
	binPath := lib.SetupFakeRunfiles(t, GREETER)

	config := lib.TestConfig{
		Args:           []string{"direct"},
		ExpectedOutput: "Hello: direct!\n",
		// the user will execute the binary directly in the bazel-bin tree
		Target: binPath,
		Cwd:    path.Dir(binPath),
	}
	lib.CheckExecutableOutput(t, &config)
}

func TestBootstrapEnvVars(t *testing.T) {
	binPath, _ := files.BinPath(GREETER)
	config := lib.TestConfig{
		Args:           []string{},
		ExpectedOutput: "",
		Target:         binPath,
	}
	lib.CheckExecutableOutput(t, &config)
	env := make(map[string]string)

	for _, line := range strings.Split(config.Result, "*~*") {
		if line == "" {
			continue
		}
		parts := strings.Split(line, "=")
		env[parts[0]] = parts[1]
	}

	_ = checkEnv(t, env, "RUNFILES_DIR")
	_ = checkEnv(t, env, "DOTNET_MULTILEVEL_LOOKUP")

	actualRunfiles := checkEnv(t, env, "RUNFILES_DIR")

	expectedRunfiles := files.ComputeRunfilesDir(os.Args[0])

	fmt.Println(expectedRunfiles)

	assert.Equal(t, expectedRunfiles, actualRunfiles)

	if runtime.GOOS == "windows" {
		manifestFile := checkEnv(t, env, "RUNFILES_MANIFEST_FILE")
		assert.Equal(t, actualRunfiles+"/MANIFEST", manifestFile)
	}
}

func checkEnv(t *testing.T, env map[string]string, key string) string {
	value, ok := env[key]
	assert.True(t, ok, "missing required environment key: '%s'", value)
	return value
}
