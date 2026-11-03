from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path
from unittest import mock

sys.path.append(str(Path(__file__).resolve().parents[1]))
sys.path.append(str(Path(__file__).resolve().parent))

import setup_retention as retention
from setup_journal import JournalStore
from setup_protocol import SetupBridgeError, decode_request
from test_setup_wifi_renew import seed_completed_usb_transaction, _seal, DEVICE, TEAM_ID
import test_setup_b1 as fixtures


class SetupRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.store = JournalStore(self.root / "state")
        self.now = time.time()

    def archive(self, days=150, *, device=DEVICE, completed=True):
        setup_id, _ = seed_completed_usb_transaction(self.store)
        journal = self.store.read()
        if device != DEVICE:
            journal["deviceID"] = device
            journal["intent"]["deviceObservation"]["deviceID"] = device
            journal["activationReceipt"]["deviceID"] = device
        if not completed:
            journal["stages"]["complete"]["state"] = "pending"
        _seal(journal)
        self.store.update(journal)
        path = self.store.transaction_root(setup_id)
        for name in ("build", "support", "support.actual"):
            (path / name).mkdir(mode=0o700)
            (path / name / "large.bin").write_bytes(b"rebuildable")
        with self.store.lock():
            archive = (self.store.archive_completed_locked if completed else self.store.abandon_unfinished_locked)(setup_id, device)
        stamp = self.now - days * 86400
        os.utime(archive, (stamp, stamp))
        return path

    def current(self):
        setup_id, _ = seed_completed_usb_transaction(self.store)
        return self.store.transaction_root(setup_id)

    def clean(self):
        with self.store.lock():
            retention.retain_archives_locked(self.store, now=self.now)

    def test_existing_history_prunes_products_and_bounds_transactions(self):
        paths = [self.archive(days=200-index) for index in range(30)]
        recent = self.archive(days=5, completed=False)
        other_device = self.archive(days=300, device="1" * 40)
        current = self.current()
        evidence = {p: ((p / "pairing.candidate").read_bytes(), (p / "journal.completed.json").read_bytes()) for p in paths}
        self.clean()
        # One latest success per device; count applies to the other archives.
        kept = {current, other_device, paths[-1], recent, *paths[-10:-1]}
        self.assertEqual(set(current.parent.iterdir()), kept)
        for path in paths[-10:-1]:
            self.assertFalse(any((path / name).exists() for name in retention._LARGE_PATHS))
            self.assertEqual((path / "pairing.candidate").read_bytes(), evidence[path][0])
            self.assertEqual((path / "journal.completed.json").read_bytes(), evidence[path][1])
            self.assertEqual(set(json.loads((path / "pruned.json").read_bytes())["paths"]), set(retention._LARGE_PATHS))
        self.assertTrue((other_device / "support").is_dir())
        records = [json.loads(line) for line in (self.store.root / "retention-log.jsonl").read_bytes().splitlines()]
        deleted = {r["setupID"] for r in records if r["result"] == "deleting"}
        self.assertEqual(deleted, {p.name for p in paths if p not in kept})
        self.assertTrue(all(r["pairingSHA256"] == hashlib.sha256(b"verified existing Wi-Fi pairing").hexdigest() for r in records if r["result"] == "deleting"))

    def test_old_wifi_pairing_source_is_untouched(self):
        source = self.archive(days=500)
        for index in range(12):
            self.archive(days=200-index)
        current = self.current()
        journal = self.store.read()
        journal["intent"].update(wifiRenew=True, fullSetup=True, transport="wifi", pairingSourceSetupID=source.name)
        journal["intent"]["deviceObservation"]["transport"] = "Network"
        journal["pairing"]["candidate"] = f"transactions/{source.name}/pairing.candidate"
        journal["delivery"]["state"] = "notStarted"
        _seal(journal)
        self.store.update(journal)
        before = {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()}
        self.clean()
        self.assertEqual(before, {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()})
        self.assertTrue(self.store._completed_eligible(self.store.read()))
        producer = fixtures.RenewB1Tests().producer(str(self.root), fixtures.RenewDevice())
        self.assertEqual(producer._wifi_pairing_source(DEVICE, TEAM_ID)["sourceSetupID"], source.name)
        self.assertTrue(current.exists())

    def test_current_quarantine_unknown_and_unsafe_types_are_preserved(self):
        collision = self.archive(days=501)
        tombstone = collision.parent / (".deleting-" + collision.name)
        tombstone.mkdir(mode=0o700)
        malformed = self.archive(days=502)
        bad_journal = malformed / "journal.completed.json"
        bad = json.loads(bad_journal.read_bytes())
        bad["proof"]["pairingImported"] = False
        bad_journal.write_text(json.dumps(bad))
        quarantine = self.archive(days=500)
        (quarantine / "incoming.plist.retiring-old").write_bytes(b"handoff")
        staging = self.archive(days=499)
        (staging / "support" / "input.staging").mkdir()
        consuming = self.archive(days=498)
        (consuming / "incoming.plist.consuming").write_bytes(b"claimed")
        unsafe = self.archive(days=497)
        (unsafe / "support.actual" / "large.bin").unlink()
        (unsafe / "support.actual").rmdir()
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "keep").write_bytes(b"untouched")
        (unsafe / "support.actual").symlink_to(outside, target_is_directory=True)
        wrong_type = self.archive(days=496)
        (wrong_type / "build" / "large.bin").unlink()
        (wrong_type / "build").rmdir()
        (wrong_type / "build").write_bytes(b"unexpected regular file")
        unknown = self.store.transaction_root(str(uuid.uuid4()))
        (unknown / "keep").write_bytes(b"unknown")
        for index in range(12):
            self.archive(days=200-index)
        current = self.current()
        before = (self.store.journal_path.read_bytes(), (current / "artifact" / "GoFly.app").stat().st_ino)
        self.clean()
        self.assertTrue(tombstone.is_dir())
        self.assertTrue((malformed / "support" / "large.bin").is_file())
        self.assertNotIn(collision.name, json.loads((self.store.root / "retention-pending.json").read_bytes()))
        for path in (quarantine, consuming, unsafe, wrong_type):
            self.assertTrue((path / "support" / "large.bin").is_file())
        # Staging inside a product tree is a Mac-local temporary, not a handoff file.
        self.assertFalse((staging / "support").exists())
        self.assertEqual((unknown / "keep").read_bytes(), b"unknown")
        self.assertEqual((outside / "keep").read_bytes(), b"untouched")
        self.assertTrue((unsafe / "support.actual").is_symlink())
        self.assertEqual(before, (self.store.journal_path.read_bytes(), (current / "artifact" / "GoFly.app").stat().st_ino))
        self.assertIn(b"skipped-unsafe-contents", (self.store.root / "retention-log.jsonl").read_bytes())

    def test_failed_build_and_support_staging_are_reclaimed_and_skips_logged_once(self):
        failed = self.archive(days=500, completed=False)
        (failed / "xcodebuild-error.txt").write_bytes(b"error: build failed")
        (failed / "xcodebuild-error.txt").chmod(0o600)
        fetch = failed / (".support." + "0" * 24 + ".staging")
        fetch.mkdir(mode=0o700)
        (fetch / (".Image.dmg." + "1" * 24 + ".staging")).write_bytes(b"partial")
        unknown = self.store.transaction_root(str(uuid.uuid4()))
        (unknown / "keep").write_bytes(b"unknown")
        for index in range(11):
            self.archive(days=200-index)
        self.current()
        self.clean()
        self.clean()
        self.assertFalse(failed.exists())
        self.assertTrue(unknown.exists())
        log = (self.store.root / "retention-log.jsonl").read_bytes()
        self.assertEqual(log.count(unknown.name.encode()), 1)

    def test_cleanup_failure_does_not_fail_apply_and_tombstone_retries(self):
        old = self.archive(days=500)
        for index in range(11):
            self.archive(days=200-index)
        helper = fixtures.RenewB1Tests()
        producer = helper.producer(str(self.root), fixtures.RenewDevice())
        def handoff(journal, *_args):
            journal = producer.store.checkpoint(journal, "support", "confirmed", proof={"supportObserved": True})
            return producer.store.checkpoint(journal, "handoff", "confirmed", proof={"pairingImported": True})
        def interrupted(_path, _record):
            # Verify the hook still holds the producer's operation lock.
            with self.assertRaisesRegex(SetupBridgeError, "busy"):
                with self.store.lock():
                    self.fail("lock unexpectedly available")
            raise OSError("interrupted after rename")
        with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact), \
             mock.patch.object(producer, "_handoff", side_effect=handoff), \
             mock.patch.object(retention, "_delete", side_effect=interrupted):
            result = producer.handle(decode_request(json.dumps(fixtures.request("apply", mode="renew", options=helper.options(self.root))).encode()))
        self.assertEqual((result.stage, result.outcome), ("complete", "confirmed"))
        self.assertTrue(result.installation_confirmed and result.pairing_imported and result.support_observed)
        tombstone = old.parent / (".deleting-" + old.name)
        self.assertTrue(tombstone.is_dir())
        self.assertFalse(old.exists())
        # Even failure after all file unlinks can recover without the rotated log.
        for child in tombstone.iterdir():
            child.unlink()
        log = self.store.root / "retention-log.jsonl"
        log.write_bytes(b'{"result":"rotated"}\n' * retention.RETAIN_LOG_LINES)
        self.clean()
        self.assertFalse(tombstone.exists())
        self.assertEqual(json.loads((self.store.root / "retention-pending.json").read_bytes()), {})
        self.assertLessEqual(len(log.read_bytes().splitlines()), retention.RETAIN_LOG_LINES)

    def test_prune_io_failure_retries_and_log_failure_keeps_install_result(self):
        old = self.archive(days=5)
        self.archive(days=1)
        self.current()
        with mock.patch.object(retention, "_remove_tree", side_effect=OSError("controlled I/O failure")):
            self.clean()
        self.assertTrue((old / "support").exists())
        self.assertIn(b"prune-failed", (self.store.root / "retention-log.jsonl").read_bytes())
        original_save = retention._save
        def fail_after_unlink(path, value):
            if path == old / "pruned.json" and "support" in value.get("paths", []):
                raise OSError("evidence commit failure")
            return original_save(path, value)
        with mock.patch.object(retention, "_save", side_effect=fail_after_unlink):
            self.clean()
        self.assertFalse((old / "support").exists())
        self.clean()
        self.assertEqual(set(json.loads((old / "pruned.json").read_bytes())["paths"]), set(retention._LARGE_PATHS))
        with mock.patch.object(retention, "_run", side_effect=OSError("disk full")), \
             mock.patch.object(retention, "_append", side_effect=OSError("disk full")), \
             self.assertLogs(retention._LOG, level="WARNING"):
            self.clean()


if __name__ == "__main__":
    unittest.main()
