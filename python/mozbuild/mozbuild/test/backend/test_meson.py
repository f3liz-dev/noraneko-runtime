# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

import os

import mozpack.path as mozpath
from mozunit import main

from mozbuild.backend.meson import MesonBackend
from mozbuild.test.backend.common import BackendTester


class TestMesonBackend(BackendTester):
    """Tests for the Meson backend."""

    def test_basic_program(self):
        """Test that a basic program generates a meson.build file."""
        try:
            env = self._consume("meson-simple", MesonBackend)

            # Check that the top-level meson.build was created
            top_meson_build = mozpath.join(env.topobjdir, "meson.build")
            self.assertTrue(
                os.path.exists(top_meson_build),
                "Top-level meson.build should exist"
            )

            # Read and verify top-level content
            with open(top_meson_build) as fh:
                content = fh.read()
                self.assertIn("project('mozilla'", content)

            # Check that a meson.build was created in the objdir
            meson_build = mozpath.join(env.topobjdir, "meson.build")
            self.assertTrue(os.path.exists(meson_build))

            with open(meson_build) as fh:
                content = fh.read()
                # Should contain program definition
                self.assertIn("test_program", content)
                self.assertIn("executable", content)
        except Exception as e:
            # Print the exception before pytest tries to format it
            import traceback
            print("\n\nACTUAL ERROR:")
            print(type(e).__name__, ":", str(e))
            traceback.print_exc()
            print("\n\n")
            raise

    def test_library(self):
        """Test that a library generates appropriate meson.build content."""
        env = self._consume("meson-library", MesonBackend)

        # Check that the top-level meson.build was created
        top_meson_build = mozpath.join(env.topobjdir, "meson.build")
        self.assertTrue(os.path.exists(top_meson_build))

        # Check that a meson.build was created
        meson_build = mozpath.join(env.topobjdir, "meson.build")
        self.assertTrue(os.path.exists(meson_build))

        with open(meson_build) as fh:
            content = fh.read()
            # Should contain library definition
            self.assertIn("library", content)

    def test_backend_output_tracking(self):
        """Test that the backend tracks its output files."""
        env = self._consume("meson-simple", MesonBackend)

        # Verify that backend.MesonBackend file was created
        backend_file = mozpath.join(env.topobjdir, "backend.MesonBackend")
        self.assertTrue(os.path.exists(backend_file))

        with open(backend_file) as fh:
            output_files = set(line.strip() for line in fh)
            # Should track at least the top-level meson.build
            self.assertIn("meson.build", output_files)


if __name__ == "__main__":
    main()
