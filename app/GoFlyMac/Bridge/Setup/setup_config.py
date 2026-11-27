"""Runtime paths derived from the GoFly app bundle."""

from __future__ import annotations

import os
import stat
from dataclasses import dataclass
from pathlib import Path

try:
    from .setup_protocol import SetupBridgeError, TARGET_NAME, is_gofly_bundle_id
except ImportError:  # script execution from the packaged Setup directory
    from setup_protocol import SetupBridgeError, TARGET_NAME, is_gofly_bundle_id


def _application_support() -> Path:
    return Path.home() / "Library" / "Application Support"


@dataclass(frozen=True)
class SetupConfiguration:
    resources_root: Path
    python_path: Path
    developer_directory: Path
    project_path: Path
    target_bundle_id: str | None
    target_name: str
    state_root: Path
    development_mode: bool = False

    @classmethod
    def from_bundle(
        cls,
        resources_root: str | Path,
        developer_directory: str | Path,
        target_bundle_id: str | None = None,
        target_name: str = TARGET_NAME,
    ) -> "SetupConfiguration":
        resources = Path(resources_root)
        return cls(
            resources_root=resources,
            python_path=resources / "Python" / "python" / "install" / "bin" / "python3.14",
            developer_directory=Path(developer_directory),
            # Only the empty signing stub ships; GoFly itself comes from the saved IPA (§5.5).
            project_path=resources / "SigningStub" / "GoFly.xcodeproj",
            target_bundle_id=target_bundle_id,
            target_name=target_name,
            state_root=_application_support() / "GoFly" / "state",
        )

    @classmethod
    def for_development(
        cls,
        workspace_root: str | Path,
        python_path: str | Path,
        developer_directory: str | Path,
        project_path: str | Path,
        target_bundle_id: str | None = None,
        target_name: str = TARGET_NAME,
    ) -> "SetupConfiguration":
        """Explicit source-tree mode for the maintainer-only iOS test script."""
        return cls(
            resources_root=Path(workspace_root),
            python_path=Path(python_path),
            developer_directory=Path(developer_directory),
            project_path=Path(project_path),
            target_bundle_id=target_bundle_id,
            target_name=target_name,
            state_root=_application_support() / "GoFly" / "state",
            development_mode=True,
        )

    def validate_read_only_paths(self) -> None:
        """Validate the fixed bundle layout without reading old app state."""
        if not self.resources_root.is_absolute() or self.resources_root.is_symlink() or not self.resources_root.is_dir():
            raise SetupBridgeError("configuration-invalid")

        if self.development_mode:
            expected_project = self.resources_root / "app" / "GoFly" / "GoFly.xcodeproj"
            expected_python = self.resources_root / "work" / "mac-setup-env" / "bin" / "python"
            expected_native = self.resources_root / "work" / "gofly-ios" / "native" / "libidevice_ffi.a"
        else:
            expected_project = self.resources_root / "SigningStub" / "GoFly.xcodeproj"
            expected_python = self.resources_root / "Python" / "python" / "install" / "bin" / "python3.14"
            expected_native = None

        expected_state = _application_support() / "GoFly" / "state"
        python_is_valid = self.python_path.is_file() and os.access(self.python_path, os.X_OK)
        if self.development_mode and self.python_path.is_symlink():
            target = self.python_path.resolve()
            python_is_valid = (
                target.name == "python3.14"
                and target.is_file()
                and os.access(target, os.X_OK)
                and (self.python_path.parent.parent / "pyvenv.cfg").is_file()
            )
        if (
            self.project_path != expected_project
            or not self.project_path.is_dir()
            or self.project_path.is_symlink()
            or self.project_path.suffix != ".xcodeproj"
            or self.python_path != expected_python
            or not python_is_valid
            or self.developer_directory.is_symlink()
            or not self.developer_directory.is_dir()
            or not (self.developer_directory / "usr" / "bin" / "xcodebuild").is_file()
            or (expected_native is not None and (not expected_native.is_file() or expected_native.is_symlink()))
            or self.state_root != expected_state
            or self.state_root.is_symlink()
            or self.target_name != TARGET_NAME
            or (self.target_bundle_id is not None and not is_gofly_bundle_id(self.target_bundle_id))
        ):
            raise SetupBridgeError("configuration-invalid")

    def ensure_state_root(self) -> Path:
        """Create only the new GoFly state directory with private permissions."""
        app_root = self.state_root.parent
        if app_root.exists() and (app_root.is_symlink() or not app_root.is_dir()):
            raise SetupBridgeError("storage-unavailable")
        if self.state_root.exists() and (self.state_root.is_symlink() or not self.state_root.is_dir()):
            raise SetupBridgeError("storage-unavailable")
        try:
            if not app_root.exists():
                app_root.mkdir(mode=0o700)
            if not self.state_root.exists():
                self.state_root.mkdir(mode=0o700)
            for path in (app_root, self.state_root):
                fd = os.open(
                    path,
                    os.O_RDONLY
                    | os.O_NOFOLLOW
                    | getattr(os, "O_DIRECTORY", 0)
                    | getattr(os, "O_NONBLOCK", 0)
                    | getattr(os, "O_CLOEXEC", 0),
                )
                try:
                    info = os.fstat(fd)
                finally:
                    os.close(fd)
                if (
                    not stat.S_ISDIR(info.st_mode)
                    or info.st_uid != os.getuid()
                    or stat.S_IMODE(info.st_mode) != 0o700
                ):
                    raise SetupBridgeError("storage-unavailable")
        except SetupBridgeError:
            raise
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None
        return self.state_root
