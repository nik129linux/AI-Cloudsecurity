"""
force_key_rotation.py

Rotates IAM access keys for a given IAM user and stores the NEW credentials in AWS Secrets Manager
(without printing or writing SecretAccessKey anywhere locally).

Key features:
- dry-run mode (no changes)
- guardrails: abort if existing keys >= max_keys (default 2)
- redacted logging (never prints SecretAccessKey)
- JSON evidence output (sanitized)
- optional deactivate_old / delete_old with explicit confirmation

Usage examples:

Dry-run:
  python3 week2/day9/force_key_rotation.py \
    --user-name rotation-lab-user \
    --secret-id lab/iam/rotation-lab-user \
    --region us-east-1 \
    --dry-run

Apply (create new key + store in Secrets Manager):
  python3 week2/day9/force_key_rotation.py \
    --user-name rotation-lab-user \
    --secret-id lab/iam/rotation-lab-user \
    --region us-east-1

Deactivate old (after you have migrated usage):
  python3 week2/day9/force_key_rotation.py \
    --user-name rotation-lab-user \
    --secret-id lab/iam/rotation-lab-user \
    --region us-east-1 \
    --deactivate-old

Delete old (lab-only, dangerous):
  python3 week2/day9/force_key_rotation.py \
    --user-name rotation-lab-user \
    --secret-id lab/iam/rotation-lab-user \
    --region us-east-1 \
    --delete-old \
    --confirm-delete DELETE
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, Optional, List

import boto3
from botocore.exceptions import ClientError


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def redacted_tail(value: Optional[str], keep_last: int = 4) -> Optional[str]:
    """Return a redacted string that only keeps the last N chars."""
    if value is None:
        return None
    if keep_last <= 0:
        return "*" * len(value)
    if len(value) <= keep_last:
        return "*" * len(value)
    return "*" * (len(value) - keep_last) + value[-keep_last:]


def write_json(path: str, payload: Dict[str, Any]) -> None:
    ensure_dir(os.path.dirname(path))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, default=str)


def iso(dt) -> str:
    try:
        return dt.isoformat()
    except Exception:
        return str(dt)


@dataclass
class RotationPlan:
    user_name: str
    secret_id: str
    region: str
    max_keys: int
    dry_run: bool
    deactivate_old: bool
    delete_old: bool
    confirm_delete: str
    evidence_dir: str
    run_id: str


def pick_old_key(keys: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """
    Pick the "old" key among existing keys (pre-rotation).
    Strategy: pick oldest by CreateDate.
    """
    if not keys:
        return None
    # keys: AccessKeyMetadata list
    return sorted(keys, key=lambda k: k["CreateDate"])[0]


def main() -> int:
    ap = argparse.ArgumentParser(description="Rotate IAM access keys and store the new one in Secrets Manager.")
    ap.add_argument("--user-name", required=True, help="IAM user to rotate keys for (lab user).")
    ap.add_argument("--secret-id", required=True, help="Secrets Manager secret name/ARN to store new creds.")
    ap.add_argument("--region", default=os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-east-1")
    ap.add_argument("--evidence-dir", default="week2/day9/evidence/rotation", help="Base directory for JSON evidence output.")

    ap.add_argument("--max-keys", type=int, default=2, help="Guardrail: abort if existing keys >= max-keys (default 2).")
    ap.add_argument("--dry-run", action="store_true", help="Plan only; do not create/modify anything.")
    ap.add_argument("--deactivate-old", action="store_true", help="Deactivate the old key after storing the new one.")
    ap.add_argument("--delete-old", action="store_true", help="Delete the old key after storing the new one (dangerous).")
    ap.add_argument("--confirm-delete", default="", help='Required for --delete-old. Must be exactly "DELETE".')

    args = ap.parse_args()

    if args.delete_old and args.c000000000000000000000000000000000000000000000000000000000000000000000000onfirm_delete != "DELETE":
        print('REFUSING: --delete-old requires --confirm-delete DELETE', file=sys.stderr)
        return 2

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    plan = RotationPlan(
        user_name=args.user_name,
        secret_id=args.secret_id,
        region=args.region,
        max_keys=args.max_keys,
        dry_run=bool(args.dry_run),
        deactivate_old=bool(args.deactivate_old),
        delete_old=bool(args.delete_old),
        confirm_delete=str(args.confirm_delete),
        evidence_dir=str(args.evidence_dir),
        run_id=run_id,
    )

    # Create clients
    iam = boto3.client("iam", region_name=plan.region)
    sm = boto3.client("secretsmanager", region_name=plan.region)
    sts = boto3.client("sts", region_name=plan.region)

    # Evidence skeleton
    evidence: Dict[str, Any] = {
        "started_at": utc_now_iso(),
        "run_id": plan.run_id,
        "inputs": {
            "user_name": plan.user_name,
            "secret_id": plan.secret_id,
            "region": plan.region,
            "max_keys": plan.max_keys,
            "dry_run": plan.dry_run,
            "deactivate_old": plan.deactivate_old,
            "delete_old": plan.delete_old,
        },
        "caller_identity": {},
        "precheck": {},
        "actions": {},
        "result": {},
        "errors": [],
        "finished_at": None,
    }

    run_dir = os.path.join(plan.evidence_dir, f"run_{plan.run_id}")
    ensure_dir(run_dir)
    out_path = os.path.join(run_dir, "result.json")

    # 1) Caller identity
    try:
        ident = sts.get_caller_identity()
        evidence["caller_identity"] = {
            "Account": ident.get("Account"),
            "Arn": ident.get("Arn"),
            "UserId": ident.get("UserId"),
        }
    except ClientError as e:
        evidence["errors"].append({"step": "sts.get_caller_identity", "error": str(e)})
        evidence["finished_at"] = utc_now_iso()
        write_json(out_path, evidence)
        print(json.dumps({"ok": False, "error": "STS get-caller-identity failed", "evidence": out_path}, indent=2))
        return 1

    # 2) Precheck: list access keys for the user
    try:
        resp = iam.list_access_keys(UserName=plan.user_name)
        existing_keys = resp.get("AccessKeyMetadata", [])
        evidence["precheck"]["existing_keys_count"] = len(existing_keys)
        evidence["precheck"]["existing_keys"] = [
            {
                "AccessKeyId": k.get("AccessKeyId"),
                "Status": k.get("Status"),
                "CreateDate": iso(k.get("CreateDate")),
            }
            for k in existing_keys
        ]
    except ClientError as e:
        evidence["errors"].append({"step": "iam.list_access_keys", "error": str(e)})
        evidence["finished_at"] = utc_now_iso()
        write_json(out_path, evidence)
        print(json.dumps({"ok": False, "error": "IAM list-access-keys failed", "evidence": out_path}, indent=2))
        return 1

    if len(existing_keys) >= plan.max_keys:
        evidence["result"]["status"] = "ABORT_TOO_MANY_KEYS"
        evidence["result"]["message"] = f"User has {len(existing_keys)} keys; max allowed is {plan.max_keys}."
        evidence["finished_at"] = utc_now_iso()
        write_json(out_path, evidence)
        print(json.dumps({"ok": False, "status": "ABORT_TOO_MANY_KEYS", "evidence": out_path}, indent=2))
        return 3

    old_key = pick_old_key(existing_keys)
    old_key_id = old_key.get("AccessKeyId") if old_key else None
    evidence["precheck"]["old_key_access_key_id"] = old_key_id

    # (Optional) Precheck: ensure secret exists (DescribeSecret)
    # We do NOT call GetSecretValue (ever).
    try:
        ds = sm.describe_secret(SecretId=plan.secret_id)
        evidence["precheck"]["secret_describe"] = {
            "Name": ds.get("Name"),
            "ARN": ds.get("ARN"),
            "DeletedDate": iso(ds.get("DeletedDate")) if ds.get("DeletedDate") else None,
            "KmsKeyId": ds.get("KmsKeyId"),
        }
    except ClientError as e:
        # If secret doesn't exist, PutSecretValue will fail anyway. We'll stop early with clear evidence.
        evidence["errors"].append({"step": "secretsmanager.describe_secret", "error": str(e)})
        evidence["result"]["status"] = "ABORT_SECRET_NOT_DESCRIBABLE"
        evidence["finished_at"] = utc_now_iso()
        write_json(out_path, evidence)
        print(json.dumps({"ok": False, "status": "ABORT_SECRET_NOT_DESCRIBABLE", "evidence": out_path}, indent=2))
        return 4

    # Plan
    evidence["precheck"]["plan"] = {
        "will_create_new_key": True,
        "will_put_secret_value": True,
        "old_key_access_key_id": old_key_id,
        "will_deactivate_old": bool(old_key_id and plan.deactivate_old),
        "will_delete_old": bool(old_key_id and plan.delete_old),
    }

    # DRY RUN exit
    if plan.dry_run:
        evidence["result"]["status"] = "DRY_RUN_OK"
        evidence["finished_at"] = utc_now_iso()
        write_json(out_path, evidence)
        print(json.dumps({"ok": True, "dry_run": True, "evidence": out_path}, indent=2))
        return 0

    # 3) Create new access key
    new_key_id = None
    new_secret_access_key = None
    try:
        created = iam.create_access_key(UserName=plan.user_name)["AccessKey"]
        new_key_id = created["AccessKeyId"]
        new_secret_access_key = created["SecretAccessKey"]  # keep in memory only
        evidence["actions"]["iam_create_access_key"] = {
            "new_access_key_id": new_key_id,
            "new_secret_access_key_redacted": redacted_tail(new_secret_access_key),
            "create_date": iso(created.get("CreateDate")),
            "status": created.get("Status", "Active"),
        }
    except ClientError as e:
        evidence["errors"].append({"step": "iam.create_access_key", "error": str(e)})
        evidence["result"]["status"] = "FAILED_CREATE_ACCESS_KEY"
        evidence["finished_at"] = utc_now_iso()
        write_json(out_path, evidence)
        print(json.dumps({"ok": False, "status": "FAILED_CREATE_ACCESS_KEY", "evidence": out_path}, indent=2))
        return 5

    # 4) Put secret value (store credentials securely)
    # IMPORTANT: Never log/print the secret string. Only store it in Secrets Manager.
    secret_payload = {
        "schema_version": 1,
        "user_name": plan.user_name,
        "access_key_id": new_key_id,
        "secret_access_key": new_secret_access_key,
        "rotated_at": utc_now_iso(),
        "rotated_from_access_key_id": old_key_id,
    }

    try:
        put = sm.put_secret_value(
            SecretId=plan.secret_id,
            SecretString=json.dumps(secret_payload),
            # Not specifying VersionStages => AWS will label it AWSCURRENT
        )
        evidence["actions"]["secretsmanager_put_secret_value"] = {
            "secret_arn": put.get("ARN"),
            "version_id": put.get("VersionId"),
            "version_stages": put.get("VersionStages", []),
        }
    except ClientError as e:
        evidence["errors"].append({"step": "secretsmanager.put_secret_value", "error": str(e)})
        evidence["result"]["status"] = "FAILED_PUT_SECRET_VALUE"

        # Rollback: delete newly created key to avoid leaving dangling creds.
        # (Best-effort; record outcome.)
        try:
            iam.delete_access_key(UserName=plan.user_name, AccessKeyId=new_key_id)
            evidence["actions"]["rollback_delete_new_key"] = {"ok": True, "access_key_id": new_key_id}
        except ClientError as e2:
            evidence["actions"]["rollback_delete_new_key"] = {"ok": False, "access_key_id": new_key_id, "error": str(e2)}

        evidence["finished_at"] = utc_now_iso()
        write_json(out_path, evidence)
        print(json.dumps({"ok": False, "status": "FAILED_PUT_SECRET_VALUE", "evidence": out_path}, indent=2))
        return 6
    finally:
        # Ensure we don't accidentally keep secret around longer than needed
        # (Python can't guarantee immediate wipe, but we can drop references.)
        new_secret_access_key = None
        secret_payload = None

    # 5) Optional: deactivate old key
    if old_key_id and plan.deactivate_old:
        try:
            iam.update_access_key(
                UserName=plan.user_name,
                AccessKeyId=old_key_id,
                Status="Inactive",
            )
            evidence["actions"]["iam_update_access_key_inactive"] = {"ok": True, "old_access_key_id": old_key_id}
        except ClientError as e:
            evidence["errors"].append({"step": "iam.update_access_key(Inactive)", "error": str(e)})
            evidence["actions"]["iam_update_access_key_inactive"] = {"ok": False, "old_access_key_id": old_key_id}

    # 6) Optional: delete old key (dangerous; lab-only)
    if old_key_id and plan.delete_old:
        try:
            iam.delete_access_key(UserName=plan.user_name, AccessKeyId=old_key_id)
            evidence["actions"]["iam_delete_access_key_old"] = {"ok": True, "old_access_key_id": old_key_id}
        except ClientError as e:
            evidence["errors"].append({"step": "iam.delete_access_key(old)", "error": str(e)})
            evidence["actions"]["iam_delete_access_key_old"] = {"ok": False, "old_access_key_id": old_key_id}

    evidence["result"]["status"] = "OK"
    evidence["result"]["new_access_key_id"] = new_key_id
    evidence["result"]["old_access_key_id"] = old_key_id
    evidence["finished_at"] = utc_now_iso()
    write_json(out_path, evidence)

    # Console output (sanitized)
    print(json.dumps({
        "ok": True,
        "status": "OK",
        "new_access_key_id": new_key_id,
        "old_access_key_id": old_key_id,
        "evidence": out_path,
        "note": "SecretAccessKey stored in Secrets Manager; never printed.",
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())