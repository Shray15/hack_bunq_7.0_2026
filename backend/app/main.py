from fastapi import FastAPI

from app.config import settings

app = FastAPI(
    title="Cooking Backend",
    version=settings.version,
)


@app.get("/healthz")
async def healthz() -> dict[str, str | bool]:
    return {
        "ok": True,
        "version": settings.version,
        "environment": settings.environment,
    }
