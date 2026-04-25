from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, Header, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models import User
from app.security import TokenError, decode_token

DbSession = Annotated[AsyncSession, Depends(get_db)]


def _user_id_from_bearer(authorization: str | None) -> uuid.UUID:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = authorization.split(" ", 1)[1].strip()
    try:
        return decode_token(token)
    except TokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"invalid token: {exc}",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


async def current_user_id(
    authorization: Annotated[str | None, Header()] = None,
) -> uuid.UUID:
    return _user_id_from_bearer(authorization)


CurrentUserId = Annotated[uuid.UUID, Depends(current_user_id)]


async def current_user(user_id: CurrentUserId, db: DbSession) -> User:
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="user not found")
    return user


CurrentUser = Annotated[User, Depends(current_user)]


async def current_user_id_query(
    token: Annotated[str | None, Query()] = None,
) -> uuid.UUID:
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing ?token= query param",
        )
    try:
        return decode_token(token)
    except TokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"invalid token: {exc}",
        ) from exc


CurrentUserIdQuery = Annotated[uuid.UUID, Depends(current_user_id_query)]
