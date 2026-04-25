from __future__ import annotations

import asyncio
import uuid

from fastapi import APIRouter, status

from app.dependencies import CurrentUserId
from app.realtime import EventName, hub
from app.schemas import ChatAccepted, ChatRequest
from app.stubs import make_recipe

router = APIRouter(tags=["chat"])

CANNED_TOKENS = [
    "Sure — ",
    "how about ",
    "lemon herb chicken ",
    "with jasmine rice? ",
    "It's high-protein, ",
    "around 570 kcal, ",
    "and fits under 25 minutes. ",
    "Generating now.",
]


async def _run_canned_chat(user_id: uuid.UUID, chat_id: uuid.UUID) -> None:
    recipe = make_recipe()

    await asyncio.sleep(0.2)
    for delta in CANNED_TOKENS:
        await hub.publish(
            user_id,
            EventName.RECIPE_TOKEN,
            {"chat_id": str(chat_id), "delta": delta},
        )
        await asyncio.sleep(0.15)

    await asyncio.sleep(0.3)
    await hub.publish(
        user_id,
        EventName.RECIPE_COMPLETE,
        {
            "chat_id": str(chat_id),
            "recipe_id": str(recipe.id),
            "recipe": recipe.model_dump(mode="json"),
        },
    )

    await asyncio.sleep(2.0)
    await hub.publish(
        user_id,
        EventName.IMAGE_READY,
        {
            "recipe_id": str(recipe.id),
            "image_url": "https://placehold.co/640x480/png?text=Lemon+Herb+Chicken",
        },
    )


@router.post("/chat", response_model=ChatAccepted, status_code=status.HTTP_202_ACCEPTED)
async def chat(payload: ChatRequest, user_id: CurrentUserId) -> ChatAccepted:
    chat_id = uuid.uuid4()
    asyncio.create_task(_run_canned_chat(user_id, chat_id))
    return ChatAccepted(chat_id=chat_id)
