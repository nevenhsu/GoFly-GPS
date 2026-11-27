from __future__ import annotations
import hashlib
import json
import plistlib
import sys
import unittest
import uuid
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1]))
from setup_adapters import (PinnedPymobiledeviceAdapter, APP_SETUP_ROOT, READBACK_REQUEST,
                            READBACK_RESPONSE, FORMAL_INPUT, ACTIVATION_RECEIPT, V1_INCOMING,
                            V1_INCOMING_CONSUMING)
from setup_protocol import SetupBridgeError, bundle_id_for_team

DEVICE = "0" * 40
PATHS = (READBACK_REQUEST, READBACK_RESPONSE, FORMAL_INPUT)
TEAM_A_BUNDLE_ID = bundle_id_for_team("ABCDEFGHIJ")


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


class MemoryAFC:
    def __init__(self):
        self.files = {}
        self.dirs = {APP_SETUP_ROOT}
        self.renames = 0
        self.fail_after = None
        self.links = set()
    async def stat(self, path):
        if path in self.links: return {"st_ifmt": "S_IFLNK", "st_size": 0}
        if path in self.dirs: return {"st_ifmt": "S_IFDIR"}
        if path not in self.files: raise FileNotFoundError(path)
        return {"st_ifmt": "S_IFREG", "st_size": len(self.files[path])}
    async def makedirs(self, path): self.dirs.add(path)
    async def listdir(self, path):
        prefix = path + "/"
        return [p[len(prefix):] for p in self.files if p.startswith(prefix) and "/" not in p[len(prefix):]]
    async def fopen(self, path, mode): return [path, 0]
    async def fread(self, handle, size):
        value = self.files[handle[0]][handle[1]:handle[1]+size]
        handle[1] += len(value)
        return value
    async def fclose(self, handle): pass
    async def rename(self, source, target):
        if self.fail_after is not None and self.renames >= self.fail_after:
            raise OSError("controlled interrupted rename")
        if target in self.files or target in self.dirs:
            raise FileExistsError(target)
        self.files[target] = self.files.pop(source)
        self.renames += 1


def completed_fixture(service):
    setup, nonce = str(uuid.uuid4()), str(uuid.uuid4())
    app = {"bundleID": TEAM_A_BUNDLE_ID, "build": "26", "profileSHA256": "a"*64, "executableSHA256": "b"*64}
    formal = {"version": 1, "setupID": setup, "nonce": nonce, "expectedDeviceUDID": DEVICE,
              "pairingTransactionID": str(uuid.uuid4()), "pairingSHA256": "c"*64, "app": app,
              "teamID": "ABCDEFGHIJ", "signingExpiry": "2030-01-01T00:00:00Z",
              "deviceOS": "26.0", "method": "personalized", "artifacts": []}
    for name in ("MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"):
        content = b"personalized" if name == "MountMethod" else b"fixture"
        formal["artifacts"].append({"id": str(uuid.uuid4()), "filename": name, "byteCount": len(content), "sha256": hashlib.sha256(content).hexdigest()})
    request = {key: formal[key] for key in ("version", "setupID", "nonce", "expectedDeviceUDID", "app")}
    response = dict(request, pairing={"kind": "absent"})
    receipt = dict(formal, rawManifestSHA256=hashlib.sha256(encoded(formal)).hexdigest(), generationID=setup, status="committed")
    service.files.update({READBACK_REQUEST: encoded(request), READBACK_RESPONSE: encoded(response),
                          FORMAL_INPUT: encoded(formal), ACTIVATION_RECEIPT: encoded({"version": 1, "activeSetupID": setup, "receipts": [receipt]})})
    return setup, nonce


class HandoffRolloverTests(unittest.TestCase):
    def setUp(self):
        self.service = MemoryAFC()
        self.adapter = PinnedPymobiledeviceAdapter(target_bundle_id=TEAM_A_BUNDLE_ID)
    def retire(self): self.adapter._retire_completed_controls(self.service, device_id=DEVICE)
    def test_fresh_container_does_not_write(self):
        self.retire()
        self.assertEqual(self.service.renames, 0)

    def test_wifi_rollover_archives_previous_controls_and_keeps_active_receipt(self):
        setup, nonce = completed_fixture(self.service)
        controls = {path: self.service.files[path] for path in PATHS}
        activation = self.service.files[ACTIVATION_RECEIPT]
        self.adapter._prepare_wifi_controls(self.service, device_id=DEVICE, manifest=controls[FORMAL_INPUT])
        self.assertEqual(self.service.renames, 0)

        self.adapter._prepare_wifi_controls(self.service, device_id=DEVICE, manifest=b"new manifest")
        for path, content in controls.items():
            self.assertNotIn(path, self.service.files)
            archived = f"{APP_SETUP_ROOT}/retired/{setup}-{nonce}/{path.rsplit('/', 1)[1]}"
            self.assertEqual(self.service.files[archived], content)
        self.assertEqual(self.service.files[ACTIVATION_RECEIPT], activation)

        self.service.files[FORMAL_INPUT] = b"previous Wi-Fi manifest"
        self.adapter._prepare_wifi_controls(self.service, device_id=DEVICE, manifest=b"next Wi-Fi manifest")
        self.assertNotIn(FORMAL_INPUT, self.service.files)
        self.assertEqual(list(self.abandoned().values()), [b"previous Wi-Fi manifest"])
        self.assertEqual(self.service.files[ACTIVATION_RECEIPT], activation)

    def test_wifi_rollover_rejects_staging_and_pairing_claims_even_without_controls(self):
        for path in (FORMAL_INPUT + ".staging", V1_INCOMING, V1_INCOMING + ".staging", V1_INCOMING_CONSUMING):
            with self.subTest(path=path):
                self.service.files = {path: b"in progress"}
                with self.assertRaisesRegex(SetupBridgeError, "transaction-unknown"):
                    self.adapter._prepare_wifi_controls(self.service, device_id=DEVICE, manifest=b"new manifest")
                self.assertEqual(self.service.files, {path: b"in progress"})

    def test_two_completed_transactions_archive_only_controls(self):
        self.service.files['Documents/favorites.json'] = b'user data'
        for _ in range(2):
            setup, nonce = completed_fixture(self.service)
            expected = {path: self.service.files[path] for path in PATHS}
            activation = self.service.files[ACTIVATION_RECEIPT]
            self.retire()
            for path in PATHS:
                self.assertNotIn(path, self.service.files)
                archived = f"{APP_SETUP_ROOT}/retired/{setup}-{nonce}/{path.rsplit('/',1)[1]}"
                self.assertEqual(self.service.files[archived], expected[path])
            self.assertEqual(self.service.files[ACTIVATION_RECEIPT], activation)
        self.assertEqual(self.service.files['Documents/favorites.json'], b'user data')
    def abandoned(self):
        return {p: v for p, v in self.service.files.items() if "/retired/abandoned-" in p}

    def test_partial_roots_are_archived_not_deleted(self):
        for absent in PATHS:
            with self.subTest(absent=absent):
                self.service = MemoryAFC(); completed_fixture(self.service)
                activation = self.service.files[ACTIVATION_RECEIPT]
                kept = {path: self.service.files[path] for path in PATHS if path != absent}
                del self.service.files[absent]
                self.retire()
                for path in PATHS: self.assertNotIn(path, self.service.files)
                self.assertEqual(sorted(self.abandoned().values()), sorted(kept.values()))
                self.assertEqual(self.service.files[ACTIVATION_RECEIPT], activation)

    def test_interrupted_rename_is_finished_by_the_next_attempt_without_loss(self):
        for fail_after in range(3):
            with self.subTest(fail_after=fail_after):
                self.service = MemoryAFC(); completed_fixture(self.service)
                originals = sorted(self.service.files[p] for p in PATHS)
                self.service.fail_after = fail_after
                with self.assertRaises(SetupBridgeError): self.retire()
                self.service.fail_after = None
                self.retire()
                for path in PATHS: self.assertNotIn(path, self.service.files)
                archived = sorted(v for p, v in self.service.files.items() if "/retired/" in p)
                self.assertEqual(archived, originals)

    def test_finished_archive_without_new_publish_is_a_noop_retry(self):
        completed_fixture(self.service)
        self.retire()
        self.retire()
        self.assertEqual(self.service.renames, 3)

    def test_existing_archive_even_empty_moves_controls_aside_as_abandoned(self):
        setup, nonce = completed_fixture(self.service)
        originals = sorted(self.service.files[p] for p in PATHS)
        self.service.dirs.add(f"{APP_SETUP_ROOT}/retired/{setup}-{nonce}")
        self.retire()
        for path in PATHS: self.assertNotIn(path, self.service.files)
        self.assertEqual(sorted(self.abandoned().values()), originals)

    def test_inactive_receipt_controls_are_archived_as_abandoned(self):
        completed_fixture(self.service)
        originals = sorted(self.service.files[p] for p in PATHS)
        active = json.loads(self.service.files[ACTIVATION_RECEIPT])
        active['activeSetupID'] = str(uuid.uuid4())
        self.service.files[ACTIVATION_RECEIPT] = encoded(active)
        self.retire()
        for path in PATHS: self.assertNotIn(path, self.service.files)
        self.assertEqual(sorted(self.abandoned().values()), originals)
        self.assertEqual(json.loads(self.service.files[ACTIVATION_RECEIPT]), active)

    def test_pending_staging_foreign_or_mismatched_controls_fail(self):
        for variant in ('pending', 'staging', 'foreign', 'tamper', 'response', 'symlink'):
            with self.subTest(variant=variant):
                self.service = MemoryAFC(); completed_fixture(self.service)
                if variant == 'pending': self.service.files[V1_INCOMING] = b'pending'
                if variant == 'staging': self.service.files[FORMAL_INPUT+'.staging'] = b'pending'
                if variant == 'foreign':
                    request = json.loads(self.service.files[READBACK_REQUEST]); request['expectedDeviceUDID'] = '1'*40
                    self.service.files[READBACK_REQUEST] = encoded(request)
                if variant == 'tamper': self.service.files[FORMAL_INPUT] += b' '
                if variant == 'response':
                    response = json.loads(self.service.files[READBACK_RESPONSE]); response['app']['build'] = 'wrong'
                    self.service.files[READBACK_RESPONSE] = encoded(response)
                if variant == 'symlink': self.service.links.add(READBACK_RESPONSE)
                with self.assertRaises(SetupBridgeError): self.retire()
                self.assertEqual(self.service.renames, 0)


class PendingPairingRetirementTests(unittest.TestCase):
    class IncomingService:
        def __init__(self, files):
            self.files = dict(files)
            self.removed = []
            self.on_remove = None
            self.race_consumer_on_retirement = False

        async def stat(self, path):
            if path not in self.files:
                raise FileNotFoundError(path)
            return {"st_ifmt": "S_IFREG", "st_size": len(self.files[path])}

        async def fopen(self, path, _mode):
            return [path, 0]

        async def fread(self, handle, size):
            value = self.files[handle[0]][handle[1]:handle[1] + size]
            handle[1] += len(value)
            return value

        async def fclose(self, _handle):
            return None

        async def rm_single(self, path, force=False):
            if force:
                if self.on_remove is not None:
                    self.on_remove(self, path)
                self.removed.append(path)
                self.files.pop(path, None)

        async def rename(self, source, target):
            if self.race_consumer_on_retirement and ".retiring-" in target:
                self.race_consumer_on_retirement = False
                self.files[V1_INCOMING_CONSUMING] = self.files.pop(source)
                raise FileNotFoundError(source)
            if source not in self.files or target in self.files:
                raise FileNotFoundError(source)
            self.files[target] = self.files.pop(source)

    def payload(self, transaction_id, device=DEVICE, pairing=b"one-shot-pairing"):
        return plistlib.dumps({
            "version": 1,
            "transactionID": transaction_id,
            "expectedDeviceUDID": device,
            "pairingFile": pairing,
            "sha256": hashlib.sha256(pairing).digest(),
        })

    def retire(self, service, transaction_id, device=DEVICE):
        PinnedPymobiledeviceAdapter._retire_pending_pairing_on_service(
            service, device_id=device, transaction_id=transaction_id.lower()
        )

    def test_removes_exact_old_incoming_only_and_preserves_active_pairing_and_user_data(self):
        transaction_id = str(uuid.uuid4())
        active_pairing = b"active pairing store"
        user_data = b"favorite and route data"
        service = self.IncomingService({
            V1_INCOMING: self.payload(transaction_id),
            "Library/LocalGo/PairingFileStore/active.plist": active_pairing,
            "Documents/user-data.json": user_data,
        })
        self.retire(service, transaction_id)
        self.assertNotIn(V1_INCOMING, service.files)
        self.assertEqual(service.removed, [V1_INCOMING + ".retiring-" + transaction_id])
        self.assertEqual(service.files["Library/LocalGo/PairingFileStore/active.plist"], active_pairing)
        self.assertEqual(service.files["Documents/user-data.json"], user_data)

    def test_missing_incoming_is_a_noop(self):
        service = self.IncomingService({"Documents/user-data.json": b"keep"})
        self.retire(service, str(uuid.uuid4()))
        self.assertEqual(service.removed, [])
        self.assertEqual(service.files, {"Documents/user-data.json": b"keep"})

    def test_mismatched_transaction_or_device_refuses_to_delete(self):
        transaction_id = str(uuid.uuid4())
        for mismatch in ("transaction", "device"):
            with self.subTest(mismatch=mismatch):
                service = self.IncomingService({
                    V1_INCOMING: self.payload(str(uuid.uuid4()) if mismatch == "transaction" else transaction_id,
                                              device="1" * 40 if mismatch == "device" else DEVICE),
                })
                with self.assertRaises(SetupBridgeError):
                    self.retire(service, transaction_id)
                self.assertIn(V1_INCOMING, service.files)
                self.assertEqual(service.removed, [])

    def test_staging_envelope_prevents_retirement(self):
        service = self.IncomingService({V1_INCOMING + ".staging": b"partial"})
        with self.assertRaises(SetupBridgeError):
            self.retire(service, str(uuid.uuid4()))
        self.assertEqual(service.removed, [])

    def test_ios_claim_wins_race_and_is_never_deleted(self):
        transaction_id = str(uuid.uuid4())
        service = self.IncomingService({V1_INCOMING: self.payload(transaction_id)})
        service.race_consumer_on_retirement = True
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            self.retire(service, transaction_id)
        self.assertIn(V1_INCOMING_CONSUMING, service.files)
        self.assertEqual(service.removed, [])

    def test_existing_ios_claim_blocks_retirement(self):
        transaction_id = str(uuid.uuid4())
        service = self.IncomingService({
            V1_INCOMING: self.payload(transaction_id),
            V1_INCOMING_CONSUMING: self.payload(transaction_id),
        })
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            self.retire(service, transaction_id)
        self.assertIn(V1_INCOMING, service.files)
        self.assertIn(V1_INCOMING_CONSUMING, service.files)
        self.assertEqual(service.removed, [])

    def test_replacement_at_well_known_path_survives_retirement(self):
        transaction_id = str(uuid.uuid4())
        replacement = self.payload(str(uuid.uuid4()), pairing=b"replacement")
        service = self.IncomingService({V1_INCOMING: self.payload(transaction_id)})

        def replace_incoming(active, path):
            if ".retiring-" in path:
                active.files[V1_INCOMING] = replacement

        service.on_remove = replace_incoming
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            self.retire(service, transaction_id)
        self.assertEqual(service.files[V1_INCOMING], replacement)
        self.assertNotIn(V1_INCOMING + ".retiring-" + transaction_id, service.files)

    def test_mismatched_quarantine_is_restored_without_deletion(self):
        expected = str(uuid.uuid4())
        source = self.payload(str(uuid.uuid4()))
        service = self.IncomingService({V1_INCOMING: source})
        with self.assertRaisesRegex(SetupBridgeError, "transaction-conflict"):
            self.retire(service, expected)
        self.assertEqual(service.files[V1_INCOMING], source)
        self.assertEqual(service.removed, [])

class CompletedJournalNonceTests(unittest.TestCase):
    def test_uuid_case_does_not_block_repeat_renew_but_other_nonce_does(self):
        import tempfile
        from setup_journal import _completed_eligible
        with tempfile.TemporaryDirectory() as directory:
            transaction = Path(directory)
            candidate = transaction/'pairing.candidate'
            candidate.write_bytes(b'fixture'); candidate.chmod(0o600)
            app_path = transaction/'artifact/GoFly.app'; app_path.mkdir(parents=True)
            setup, nonce = str(uuid.uuid4()), str(uuid.uuid4())
            artifact = dict(path=str(app_path), bundleID=TEAM_A_BUNDLE_ID, build='26',
                            artifactSHA256='a'*64, executableSHA256='b'*64,
                            profileSHA256='c'*64, teamID='ABCDEFGHIJ', expiresAt='2030-01-01T00:00:00Z')
            formal = [{'fixture': True}]
            manifest = '{}'
            manifest_hash = hashlib.sha256(manifest.encode()).hexdigest()
            tx = str(uuid.uuid4())
            pairing_bytes = b'fixture'
            pairing_sha = hashlib.sha256(pairing_bytes).hexdigest()
            candidate.write_bytes(pairing_bytes)
            activation = {key: artifact[key] for key in ('bundleID','build','profileSHA256','executableSHA256','teamID')}
            activation.update(setupID=setup,deviceID=DEVICE,nonce=nonce,rawManifestSHA256=manifest_hash,
                              pairingTransactionID=tx,pairingSHA256=pairing_sha,signingExpiry=artifact['expiresAt'],
                              deviceOS='26.0',method='personalized',generationID=setup,artifacts=formal)
            journal = dict(setupID=setup,deviceID=DEVICE,mode='renew',
                intent=dict(fullSetup=True,artifact=artifact,pairingTransactionID=tx),
                stages={key: {'state':'confirmed'} for key in ('artifact','pairing','install','support','handoff','complete')},
                proof={key:True for key in ('installationConfirmed','pairingImported','supportObserved')},
                delivery={'state':'delivered'},pairing={'candidate':f'transactions/{setup}/pairing.candidate','sha256':pairing_sha},
                support=dict(osVersion='26.0',method='personalized',generationID=setup),
                handoff=dict(nonce=nonce.upper(),manifestSHA256=manifest_hash,formalArtifacts=formal,rawManifest=manifest),
                activationReceipt=activation)
            journal['installOwnership']={key:artifact[key] for key in ('bundleID','build','artifactSHA256','executableSHA256','profileSHA256')}
            journal['installOwnership']['transactionID']=setup
            def seal():
                journal.pop('receiptSHA256',None)
                journal['receiptSHA256']=hashlib.sha256(encoded(journal)).hexdigest()
            seal()
            self.assertTrue(_completed_eligible(journal,transaction))
            activation['nonce']=str(uuid.uuid4()); seal()
            self.assertFalse(_completed_eligible(journal,transaction))

if __name__ == '__main__': unittest.main()
