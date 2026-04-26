from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", case_sensitive=False)

    version: str = "dev"
    environment: str = "local"

    database_url: str = Field(
        default="postgresql+asyncpg://cooking:cooking@localhost:5432/cooking",
        description="SQLAlchemy async URL. Overridden by deploy via DATABASE_URL env var.",
    )

    jwt_secret: str = Field(
        default="dev-insecure-secret-change-me",
        description="HS256 signing key. Required in production via env.",
    )
    jwt_algorithm: str = "HS256"
    jwt_ttl_minutes: int = 60 * 24 * 30  # 30 days

    sse_heartbeat_seconds: int = 15

    deepseek_api_key: str = ""
    deepseek_model: str = "deepseek-chat"
    deepseek_max_tokens: int = 1024
    deepseek_timeout_seconds: float = 30.0

    gemini_api_key: str = ""
    gemini_image_model: str = "gemini-2.5-flash-image"
    bunq_api_key: str = ""
    bunq_installation_token: str = ""

    gemini_timeout_seconds: float = 60.0
    chat_rate_limit_per_minute: int = 5

    # grocery-mcp connection (Phase 3). Required in production. Tests/local dev
    # set `grocery_mcp_stub=true` to skip the connection entirely.
    grocery_mcp_url: str = ""
    grocery_mcp_stub: bool = False
    grocery_mcp_connect_timeout_seconds: float = 10.0
    grocery_mcp_call_timeout_seconds: float = 10.0
    bunq_poll_interval_seconds: float = 2.0
    bunq_poll_max_seconds: float = 300.0

    # Production-style bunq.me URLs (Phase iii). We construct
    # `https://bunq.me/<handle>/<amount>/<description>` directly instead of
    # minting a sandbox BunqMeTab — sandbox URLs don't open the real iDEAL
    # flow, and the demo wants to show what a customer would actually see.
    # Override via BUNQ_ME_USERNAME in deploy `.env`.
    bunq_me_username: str = Field(
        default="HackBunqDemo",
        description="bunq.me handle used for production-style payment URLs.",
    )

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
