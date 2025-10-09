#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Firefox profile server for PGO profiling."""

from __future__ import annotations

import argparse
import glob
import os
import subprocess
import sys
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator

try:
    import mozcrash
    from mozfile import TemporaryDirectory, json
    from mozhttpd import MozHttpd
    from mozprofile import FirefoxProfile, Preferences
    from mozprofile.permissions import ServerLocations
    from mozrunner import CLI, FirefoxRunner
except ImportError:
    print(
        "Missing dependencies. Install with:\n"
        "  uv pip install mozcrash mozfile mozhttpd mozprofile mozrunner"
    )
    sys.exit(1)


@dataclass(frozen=True, slots=True)
class Config:
    """Configuration for profile server."""

    binary: Path
    source_dir: Path
    port: int = 8888
    sp3_port: int = 8000
    llvm_profdata: Path | None = None
    upload_path: Path | None = None

    PATH_MAPPINGS = {
        "/webkit/PerformanceTests": "third_party/webkit/PerformanceTests",
        "/talos": "testing/talos/talos",
    }

    def __post_init__(self) -> None:
        for field in ("binary", "source_dir"):
            path = getattr(self, field)
            if not isinstance(path, Path):
                object.__setattr__(self, field, Path(path).resolve())

        if not self.binary.exists():
            raise FileNotFoundError(f"Binary not found: {self.binary}")
        if not self.source_dir.exists():
            raise FileNotFoundError(f"Source dir not found: {self.source_dir}")


@contextmanager
def http_servers(config: Config) -> Iterator[tuple[MozHttpd, MozHttpd]]:
    """Start and manage HTTP servers."""
    path_mappings = {
        k: os.path.join(config.source_dir, v) for k, v in config.PATH_MAPPINGS.items()
    }

    httpd = MozHttpd(
        port=config.port,
        docroot=os.path.join(config.source_dir, "build", "pgo"),
        path_mappings=path_mappings,
    )

    sp3_httpd = MozHttpd(
        port=config.sp3_port,
        docroot=os.path.join(
            config.source_dir,
            "third_party",
            "webkit",
            "PerformanceTests",
            "Speedometer3",
        ),
        path_mappings=path_mappings,
    )

    try:
        httpd.start(block=False)
        sp3_httpd.start(block=False)
        print(f"started SP3 server on port {config.sp3_port}")
        yield httpd, sp3_httpd
    finally:
        sp3_httpd.stop()
        httpd.stop()


def load_preferences(config: Config) -> dict[str, object]:
    """Load preferences from profile configuration."""
    profile_dir = os.path.join(config.source_dir, "testing", "profiles")
    profiles_json = os.path.join(profile_dir, "profiles.json")

    with open(profiles_json) as fh:
        base_profiles = json.load(fh)["profileserver"]

    prefs = {}
    for profile in base_profiles:
        pref_file = os.path.join(profile_dir, profile, "user.js")
        prefs.update(Preferences.read_prefs(pref_file))

    return prefs


def create_profile(
    config: Config, profile_path: str, httpd: MozHttpd
) -> FirefoxProfile:
    """Create Firefox profile with configuration."""
    prefs = load_preferences(config)

    interpolation = {"server": "%s:%d" % httpd.httpd.server_address}
    # Note: sp3_interpolation is defined in original but never used
    # sp3_interpolation = {"server": "%s:%d" % sp3_httpd.httpd.server_address}
    for k, v in prefs.items():
        if isinstance(v, str):
            v = v.format(**interpolation)
        prefs[k] = Preferences.cast(v)

    locations = ServerLocations()
    locations.add_host(
        host="127.0.0.1", port=config.port, options="primary,privileged"
    )

    quitter = os.path.join(
        config.source_dir, "tools", "quitter", "quitter@mozilla.org.xpi"
    )

    return FirefoxProfile(
        profile=profile_path,
        preferences=prefs,
        addons=[quitter],
        locations=locations,
    )


def get_crashreports(directory: str, name: str | None = None) -> int:
    """Process crash reports if found."""
    rc = 0
    upload_path = os.environ.get("UPLOAD_PATH")
    if not upload_path:
        upload_path = os.environ.get("UPLOAD_DIR")
    if upload_path:
        fetches_dir = os.environ.get("MOZ_FETCHES_DIR")
        if not fetches_dir:
            raise Exception(
                "Unable to process minidump in automation because "
                "$MOZ_FETCHES_DIR is not set in the environment"
            )
        stackwalk_binary = os.path.join(
            fetches_dir, "minidump-stackwalk", "minidump-stackwalk"
        )
        if sys.platform == "win32":
            stackwalk_binary += ".exe"
        minidump_path = os.path.join(directory, "minidumps")
        rc = mozcrash.check_for_crashes(
            minidump_path,
            symbols_path=fetches_dir,
            stackwalk_binary=stackwalk_binary,
            dump_save_path=upload_path,
            test_name=name,
        )
    return rc


def setup_environment() -> dict[str, str]:
    """Set up environment for profiling."""
    env = os.environ.copy()
    env["MOZ_CRASHREPORTER_NO_REPORT"] = "1"
    env["MOZ_CRASHREPORTER_SHUTDOWN"] = "1"
    env["XPCOM_DEBUG_BREAK"] = "warn"
    env["LLVM_PROFILE_FILE"] = os.path.join(
        os.getcwd(), "default_%p_random_%m.profraw"
    )
    return env


def run_firefox(
    config: Config,
    profile: FirefoxProfile,
    cmdargs: list[str],
    env: dict[str, str],
    run_num: int,
    debug_args=None,
    interactive=False,
) -> int:
    """Run Firefox with given arguments."""
    process_args = {"universal_newlines": True}
    if "UPLOAD_PATH" in env:
        process_args["logfile"] = os.path.join(
            env["UPLOAD_PATH"], f"profile-run-{run_num}.log"
        )

    runner = FirefoxRunner(
        profile=profile,
        binary=str(config.binary),
        cmdargs=cmdargs,
        env=env,
        process_args=process_args,
    )
    runner.start(debug_args=debug_args, interactive=interactive)
    ret = runner.wait()

    if ret:
        print(f"Firefox exited with code {ret} during {'profile initialization' if run_num == 1 else 'profiling'}")
        logfile = process_args.get("logfile")
        if logfile:
            print(f"Firefox output ({logfile}):")
            with open(logfile) as f:
                print(f.read())

    return ret


def clean_profraw() -> None:
    """Remove old profraw files."""
    old_profraw_files = glob.glob("*.profraw")
    for f in old_profraw_files:
        os.remove(f)


def merge_profile_data(llvm_profdata: str) -> int:
    """Merge profraw files into merged.profdata."""
    profraw_files = glob.glob("*.profraw")
    if not profraw_files:
        print(f"Could not find profraw files in the current directory: {os.getcwd()}")
        return 1

    merged = "merged.profdata"
    cmd = [llvm_profdata, "merge", "-o", merged] + profraw_files

    rc = subprocess.call(cmd)
    if rc != 0:
        print("INFRA-ERROR: Failed to merge profile data. Corrupt profile?")
        return 4

    if not os.path.isfile(merged):
        print(merged, "was not created", file=sys.stderr)
        return 1

    if os.path.getsize(merged) == 0:
        print(merged, "was created but it is empty", file=sys.stderr)
        return 1

    return 0


def verify_logs(upload_path: str) -> bool:
    """Check logs for LLVM Profile Error."""
    should_err = False
    print("Verify log for LLVM Profile Error")
    # Note: range(1, 2) only checks log 1, matching original behavior
    for n in range(1, 2):
        log = os.path.join(upload_path, f"profile-run-{n}.log")
        with open(log) as f:
            for line in f.readlines():
                if "LLVM Profile Error" in line:
                    print(f"Error [{log}]: '{line.strip()}'")
                    should_err = True

    if should_err:
        print("Found some LLVM Profile Error in logs, see above.")
    return should_err


def main() -> int:
    """Run Firefox profiling session."""
    cli = CLI()
    debug_args, interactive = cli.debugger_arguments()
    runner_args = cli.runner_args()

    parser = argparse.ArgumentParser(description="Firefox PGO profile server")
    parser.add_argument("--binary", type=Path, help="Firefox binary")
    parser.add_argument(
        "--source-dir", type=Path, required=True, help="Source directory"
    )
    parser.add_argument("--port", type=int, default=8888, help="HTTP port")
    parser.add_argument("--llvm-profdata", type=Path, help="llvm-profdata binary")
    args = parser.parse_args()

    binary = runner_args.get("binary") or args.binary
    if not binary:
        print("Binary not specified. Use --binary or mozrunner CLI arguments.")
        return 1

    binary = os.path.normpath(os.path.abspath(binary))

    config = Config(
        binary=Path(binary),
        source_dir=args.source_dir,
        port=args.port,
        llvm_profdata=args.llvm_profdata or os.getenv("LLVM_PROFDATA"),
        upload_path=Path(p) if (p := os.getenv("UPLOAD_PATH")) else None,
    )

    clean_profraw()

    with http_servers(config) as (httpd, _), TemporaryDirectory() as tmpdir:
        profile = create_profile(config, tmpdir, httpd)
        env = setup_environment()

        # Initialize profile
        if ret := run_firefox(
            config,
            profile,
            ["data:text/html,<script>Quitter.quit()</script>"],
            env,
            1,
        ):
            get_crashreports(tmpdir, name="Profile initialization")
            return ret

        # Set up JAR logging
        if jarlog := os.getenv("JARLOG_FILE"):
            env["MOZ_JAR_LOG_FILE"] = os.path.abspath(jarlog)
            print(f"jarlog: {env['MOZ_JAR_LOG_FILE']}")
            if os.path.exists(jarlog):
                os.remove(jarlog)

        # Run profiling
        if ret := run_firefox(
            config,
            profile,
            [f"http://localhost:{config.port}/index.html"],
            env,
            2,
            debug_args=debug_args,
            interactive=interactive,
        ):
            get_crashreports(tmpdir, name="Profiling run")
            return ret

        # Verify logs
        if "UPLOAD_PATH" in env and verify_logs(env["UPLOAD_PATH"]):
            return 1

        # Check crashes
        if get_crashreports(tmpdir, name="Firefox exited successfully?") != 0:
            print("Firefox exited successfully, but produced a crashreport")
            return 1

        # Merge profile data
        if config.llvm_profdata:
            if ret := merge_profile_data(str(config.llvm_profdata)):
                return ret

    return 0


if __name__ == "__main__":
    sys.exit(main())
