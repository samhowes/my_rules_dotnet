package files

import (
	"github.com/bazelbuild/rules_go/go/tools/bazel"
	"os"
	"path"
	"runtime"
	"strings"
	"sync"
)

var Info = struct {
	once      sync.Once
	pkg       string
	workspace string
	target    string
}{}

func initInfo() {
	Info.once.Do(func() {
		Info.target = os.Getenv("TEST_TARGET")
		Info.workspace = os.Getenv("TEST_WORKSPACE")
		Info.pkg = strings.Split(Info.target, ":")[0][2:]
	})
}

func Path(packageRelative string) (string, error) {
	initInfo()
	var rpath string
	if packageRelative[0] == '@' {
		rpath = packageRelative[1:]
	} else {
		rpath = path.Join(Info.pkg, packageRelative)
	}

	fpath, err := bazel.Runfile(rpath) // yolo on the err, totally won't regret
	return fpath, err
}

func BinName(maybeExe string) string {
	if runtime.GOOS == "windows" && !strings.HasSuffix(maybeExe, ".exe") {
		return maybeExe + ".exe"
	}
	return maybeExe
}

func BinPath(packageRelativeMaybeExe string) (string, error) {
	return Path(BinName(packageRelativeMaybeExe))
}

func EndingsB(byteArray []byte) string {
	return Endings(string(byteArray))
}

func Endings(maybeCrlf string) string {
	if runtime.GOOS == "windows" {
		return strings.Replace(maybeCrlf, "\r\n", "\n", -1)
	}
	return maybeCrlf
}

func PosixPath(maybeWinPath string) string {
	if os.PathSeparator == '\\' {
		return strings.Replace(maybeWinPath, "\\", "/", -1)
	}
	return maybeWinPath
}

func ComputeRunfilesDir(arg0 string) string {
	if runtime.GOOS == "windows" {
		// no symlinking happens on windows, so arg0 is the exact artifact that is built
		return PosixPath(arg0) + ".runfiles"
	}
	// in tests, in go, we are symlinked into the tree and started in the tree, so arg0 is prefixed with the
	//runfiles dir
	endIndex := strings.Index(arg0, ".runfiles") + len(".runfiles")
	return arg0[0:endIndex]
}

func ComputeStartingDir(arg0 string) string {
	initInfo()
	runfilesDir := PosixPath(arg0) + ".runfiles"
	startingDir := path.Join(runfilesDir, Info.workspace)
	return startingDir
}
