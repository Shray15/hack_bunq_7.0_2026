from __future__ import annotations

import uuid

from fastapi import APIRouter, HTTPException, status

from app.dependencies import CurrentUserId, DbSession
from app.orchestrator import meal_share_flow
from app.schemas.meal_share import ShareCostCreate, ShareCostOut

router = APIRouter(tags=["meal-share"])


@router.post(
    "/orders/{order_id}/share-cost",
    response_model=ShareCostOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_share(
    order_id: uuid.UUID,
    payload: ShareCostCreate,
    user_id: CurrentUserId,
    db: DbSession,
) -> ShareCostOut:
    return await meal_share_flow.create_share(
        db=db,
        user_id=user_id,
        order_id=order_id,
        participant_count=payload.participant_count,
        include_self=payload.include_self,
    )


@router.get(
    "/orders/{order_id}/share-cost",
    response_model=ShareCostOut,
)
async def get_share(
    order_id: uuid.UUID,
    user_id: CurrentUserId,
    db: DbSession,
) -> ShareCostOut:
    share = await meal_share_flow.get_latest_share(
        db=db, user_id=user_id, order_id=order_id
    )
    if share is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="no share-cost link for this order yet",
        )
    return share
