import io
import tempfile
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
import types, sys

# Provide dummy requests module for imports
sys.modules.setdefault('requests', types.ModuleType('requests'))
# Minimal YAML stub for ConfigManager import
yaml_mod = types.ModuleType('yaml')
yaml_mod.safe_load = lambda *a, **k: {}
sys.modules.setdefault('yaml', yaml_mod)

from backup.tools.lib.mount import BackupMounter

class OpenLuksDeviceTest(unittest.TestCase):
    def test_existing_mapper_generates_unique_name(self):
        tmp = tempfile.TemporaryDirectory()
        base_dir = Path(tmp.name)
        server_dir = base_dir / "store" / "srv"
        server_dir.mkdir(parents=True)
        device = server_dir / "backups"
        device.touch()

        mounter = BackupMounter(str(base_dir))
        orig_name = "srv.mounted"

        def fake_exists(self):
            if str(self) == f"/dev/mapper/{orig_name}":
                return True
            return Path.__orig_exists__(self)

        Path.__orig_exists__ = Path.exists

        def mock_run(cmd, *args, **kwargs):
            if cmd[0] == "dmsetup" and cmd[1] == "ls":
                return subprocess.CompletedProcess(cmd, 0, stdout=f"{orig_name}\t(253,0)\n", stderr="")
            if cmd[:2] == ["cryptsetup", "luksClose"]:
                return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
            if cmd[:2] == ["dmsetup", "remove"]:
                return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="busy")
            if cmd[0] == "umount":
                return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
            if cmd[:2] == ["cryptsetup", "luksOpen"]:
                return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        class DummyPopen:
            def __init__(self, *a, **kw):
                self.stdout = io.BytesIO(b"pass")

        with patch.object(Path, "exists", fake_exists), \
             patch.object(BackupMounter, "_generate_unique_device_name", return_value="unique_mapper"), \
             patch("subprocess.run", side_effect=mock_run), \
             patch("subprocess.Popen", return_value=DummyPopen()):
            success, msg = mounter._open_luks_device(str(device), orig_name, "pass")

        self.assertTrue(success)
        with open(server_dir / "device_name") as f:
            self.assertEqual(f.read().strip(), "unique_mapper")
        self.assertIn("unique_mapper", msg)

class MountDirectoryTest(unittest.TestCase):
    def test_mount_uses_device_name_file(self):
        tmp = tempfile.TemporaryDirectory()
        base_dir = Path(tmp.name)
        server_dir = base_dir / "store" / "srv"
        server_dir.mkdir(parents=True)

        # minimal config
        with open(server_dir / "server.config", "w") as f:
            f.write('ENCRYPTED="1"\n')

        # device name file and passphrase
        with open(server_dir / "device_name", "w") as f:
            f.write("dname")
        with open(server_dir / "passphrase", "w") as f:
            f.write("pass")

        mounter = BackupMounter(str(base_dir))

        with patch.object(BackupMounter, "_is_mounted", return_value=False), \
             patch.object(BackupMounter, "_open_luks_device", return_value=(True, "ok")) as open_mock, \
             patch.object(BackupMounter, "_mount_device", return_value=(True, "ok")) as mount_mock:
            success, msg = mounter.mount_backup_directory("srv")

        self.assertTrue(success)
        open_mock.assert_called_once_with(str(server_dir / "backups"), "dname", "pass")
        mount_mock.assert_called_once_with("/dev/mapper/dname", str(server_dir / ".mounted"))

if __name__ == "__main__":
    unittest.main()
