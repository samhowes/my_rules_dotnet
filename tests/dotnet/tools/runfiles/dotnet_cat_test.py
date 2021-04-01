import os

from rules_python.python.runfiles import runfiles

from tests.tools import mypytest
from tests.tools.executable import Executable


class TestLauncher(object):
    @classmethod
    def setup_class(cls):
        cls.r = runfiles.Create()

    def get_contents(self, rpath):
        fpath = self.r.Rlocation(rpath)
        with open(fpath) as f:
            contents = f.read()
        return contents

    def test_run_genrule_works(self):
        contents = self.get_contents(os.environ.get("RUN_RESULT"))
        assert "Hello Runfiles!\n" == contents

    def test_run_data_dep_works(self):
        env = self.r.EnvVars()
        executable = Executable(self.r.Rlocation("TARGET_BINARY"))
        contents = self.assert_success(executable, env)
        assert "Hello Runfiles!\n" == contents

    def assert_success(self, executable, env, cwd=None):
        code, stdout, stderr = executable.run([], env=env, cwd=cwd)

        assert code == 0, stderr
        assert stderr == ""
        return stdout


if __name__ == '__main__':
    mypytest.main(__file__)
