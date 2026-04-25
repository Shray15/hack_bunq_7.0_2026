from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import settings

_pwd = CryptContext(schemes=["argon2"], deprecated="auto")


def hash_password(plain: str) -> str:
    return _pwd.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return _pwd.verify(plain, hashed)


class TokenError(Exception):
    pass


def create_access_token(user_id: uuid.UUID, *, ttl_minutes: int | None = None) -> str:
    now = datetime.now(UTC)
    ttl = ttl_minutes if ttl_minutes is not None else settings.jwt_ttl_minutes
    payload: dict[str, Any] = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=ttl)).timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> uuid.UUID:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError as exc:
        raise TokenError(str(exc)) from exc
    sub = payload.get("sub")
    if not isinstance(sub, str):
        raise TokenError("token missing subject")
    try:
        return uuid.UUID(sub)
    except ValueError as exc:
        raise TokenError("token subject is not a uuid") from exc
