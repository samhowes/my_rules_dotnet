package lib

import (
	"bytes"
	"github.com/bazelbuild/rules_go/go/tools/bazel"
	"github.com/samhowes/rules_msbuild/tests/tools/files"
	"github.com/stretchr/testify/assert"
	"github.com/termie/go-shutil"
	"golang.org/x/sys/execabs"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sync"
	"testing"
)

type TestConfig struct {
	Data           map[string]interface{}
	Args           []string
	ExpectedOutput string
	JsonText       string
	Target         string
	Once           sync.Once
	Cwd            string
	Result         string
	RunLocation    string
	Debug          bool
	Diag           bool
	Package        string
}

func SetupFakeRunfiles(t *testing.T, binName string) string {
	tmpDir, err := bazel.NewTmpDir(t.Name())
	if err != nil {
		t.Fatalf("failed to create tmp dir: %v", err)
	}

	fakeRunfilesDir := path.Join(tmpDir, binName+".runfiles")
	thisRunfilesDir := files.ComputeRunfilesDir(os.Args[0])
	err = shutil.CopyTree(thisRunfilesDir, fakeRunfilesDir, nil)
	t.Logf("created runfiles tree at: %s\n", fakeRunfilesDir)
	if err != nil {
		t.Fatalf("failed to create new runfiles tree: %v", err)
	}

	binPath := path.Join(path.Dir(fakeRunfilesDir), files.BinName(binName))
	srcBin, _ := files.BinPath(binName)
	t.Logf("srcBin %s\n", srcBin)
	newPath, err := shutil.Copy(srcBin, binPath, true)
	if err != nil {
		t.Fatalf("failed to copy executable: %v", err)
	}
	if newPath != binPath {
		t.Fatalf("incorrect copy:\nexpected: '%s'\nactual: '%s'", binPath, newPath)
	}

	t.Logf("%s\n", newPath)
	return binPath
}

func CheckExecutableOutput(t *testing.T, config *TestConfig) {
	abspath, err := filepath.Abs(config.Target)
	if err != nil {
		t.Fatalf("bad executable path %s:%v", path.Base(config.Target), err)
	}

	cmd := execabs.Command(abspath, config.Args...)

	if config.Cwd != "" {
		cmd.Dir = config.Cwd
	}
	cmd.Env = os.Environ()
	cmd.Stdin = nil
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Start(); err != nil {
		t.Fatalf("failed to launch command: %s\n%v", cmd.String(), err)
	}

	state, err := cmd.Process.Wait()
	if err != nil {
		t.Errorf("failed to wait on cmd %s\n%v", cmd.String(), err)
	}

	if !state.Success() {
		t.Errorf("command did not complete successfully: %s\n", state.String())
	}

	actualOut := files.Endings(stdout.String())
	config.Result = actualOut
	if config.ExpectedOutput == "" {
		return
	}

	actualErr := files.Endings(stderr.String())
	assert.Empty(t, actualErr, "command had errors")

	if config.ExpectedOutput[0] == '%' {
		expr := config.ExpectedOutput[1:]
		matched, err := regexp.Match(expr, []byte(actualOut))
		assert.NoError(t, err, "error matching output")
		assert.True(t, matched, "failed to match command output")
	} else {
		assert.Equal(t, config.ExpectedOutput, actualOut, "incorrect command output")
	}

	t.Logf("Stdout: \n'%s'", actualOut)
}

func CheckDotnetOutput(t *testing.T, assemblyPath string, expectedOutput string) {
	dotnetPath, _ := files.BinPath("@dotnet")
	config := TestConfig{
		Args:           []string{assemblyPath},
		ExpectedOutput: expectedOutput,
		Target:         dotnetPath,
	}
	os.Setenv("DOTNET_CLI_HOME", path.Dir(dotnetPath))
	os.Setenv("DOTNET_SKIP_FIRST_TIME_EXPERIENCE", "1")
	os.Setenv("DOTNET_MULTILEVEL_LOOKUP", "0")
	os.Setenv("DOTNET_NOLOGO", "0")
	t.Logf("dotnet path: %s\n", config.Target)
	CheckExecutableOutput(t, &config)
}
