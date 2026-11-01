"""The yavs on PATH, as the action leaves it, found and used by the vunit-yavs package."""

import os
from pathlib import Path

os.environ.setdefault("VUNIT_SIMULATOR", "yavs")

from vunit import VUnit  # pylint: disable=wrong-import-position

vu = VUnit.from_argv()
vu.add_package("vunit-yavs", allow_setup=True)  # first: it provides the simulator
vu.add_vhdl_builtins()
vu.add_library("tb").add_source_files(Path(__file__).parent / "tb_pass.vhd")
vu.main()
