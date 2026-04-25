import os
from dotenv import load_dotenv
from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.context.api_environment_type import ApiEnvironmentType
from bunq.sdk.context.bunq_context import BunqContext
from bunq.sdk.model.generated.endpoint import MonetaryAccountBankApiObject

load_dotenv()

API_KEY = os.getenv("BUNQ_API_KEY")
CONF_FILE = "bunq_sandbox.conf"

def setup():
    print("Creating bunq API context...")
    ctx = ApiContext.create(
        ApiEnvironmentType.SANDBOX,
        API_KEY,
        "hack-bunq-demo",
        [],
    )
    ctx.save(CONF_FILE)
    print(f"Context saved to {CONF_FILE}")

    BunqContext.load_api_context(ctx)
    accounts = MonetaryAccountBankApiObject.list().value
    print(f"\nFound {len(accounts)} account(s):")
    for acc in accounts:
        print(f"  Account ID: {acc.id_}  |  Currency: {acc.currency}  |  Status: {acc.status}")

    print("\nCopy the Account ID above into your .env as BUNQ_ACCOUNT_ID")

if __name__ == "__main__":
    setup()
