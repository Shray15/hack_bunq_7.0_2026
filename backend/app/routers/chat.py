from __future__ import annotations

import asyncio
import uuid

from fastapi import APIRouter, HTTPException, status

from app.dependencies import CurrentUser
from app.orchestrator.chat_flow import run_chat_flow
from app.schemas import ChatAccepted, ChatRequest, Profile
from app.services.rate_limit import enforce_chat_rate_limit

router = APIRouter(tags=["chat"])


@router.post("/chat", response_model=ChatAccepted, status_code=status.HTTP_202_ACCEPTED)
async def chat(payload: ChatRequest, user: CurrentUser) -> ChatAccepted:
    enforce_chat_rate_limit(user.id)
    if user.profile is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="profile missing — call PATCH /user/profile first",
        )
    profile = Profile.model_validate(user.profile)
    chat_id = uuid.uuid4()
    asyncio.create_task(
        run_chat_flow(
            user_id=user.id,
            chat_id=chat_id,
            transcript=payload.transcript,
            profile=profile,
        )
    )
    return ChatAccepted(chat_id=chat_id)
