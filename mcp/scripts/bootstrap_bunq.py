"""Idempotent bunq sandbox bootstrap.

Reads BUNQ_API_KEY from env, writes bunq_sandbox.conf + an account_id
sidecar to BUNQ_DATA_DIR (default '.'). Safe to run repeatedly: re-uses
the existing conf and only refreshes the sidecar if it's missing.

Designed to run from the container entrypoint so deploy doesn't need
manual setup_bunq.py invocations.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.context.api_environment_type import ApiEnvironmentType
from bunq.sdk.context.bunq_context import BunqContext
from bunq.sdk.model.generated.endpoint import MonetaryAccountBankApiObject

load_dotenv()

DATA_DIR = Path(os.getenv("BUNQ_DATA_DIR", "."))
CONF_FILE = DATA_DIR / "bunq_sandbox.conf"
ACCOUNT_ID_FILE = DATA_DIR / "account_id"
DEVICE_DESCRIPTION = "hack-bunq-mcp"


def _load_or_create_context() -> ApiContext:
    if CONF_FILE.exists():
        print(f"[bootstrap_bunq] reusing existing context at {CONF_FILE}")
        return ApiContext.restore(str(CONF_FILE))

    api_key = os.getenv("BUNQ_API_KEY")
    if not api_key:
        sys.exit("[bootstrap_bunq] BUNQ_API_KEY is not set; cannot create context.")

    print(f"[bootstrap_bunq] registering new sandbox context at {CONF_FILE}")
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    ctx = ApiContext.create(
        ApiEnvironmentType.SANDBOX,
        api_key,
        DEVICE_DESCRIPTION,
        [],  # all IPs allowed in sandbox
    )
    ctx.save(str(CONF_FILE))
    return ctx


def _ensure_account_id(ctx: ApiContext) -> int:
    if ACCOUNT_ID_FILE.exists():
        return int(ACCOUNT_ID_FILE.read_text().strip())

    BunqContext.load_api_context(ctx)
    accounts = MonetaryAccountBankApiObject.list().value
    if not accounts:
        sys.exit("[bootstrap_bunq] no monetary accounts found on this user.")

    account_id = accounts[0].id_
    ACCOUNT_ID_FILE.write_text(str(account_id))
    print(f"[bootstrap_bunq] account_id={account_id} written to {ACCOUNT_ID_FILE}")
    return account_id


def main() -> int:
    ctx = _load_or_create_context()
    _ensure_account_id(ctx)
    print("[bootstrap_bunq] ready.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
