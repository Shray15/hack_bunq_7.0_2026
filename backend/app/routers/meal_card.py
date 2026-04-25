from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status

from app.dependencies import CurrentUserId, DbSession
from app.orchestrator import meal_card_flow
from app.schemas.meal_card import (
    MealCardCreate,
    MealCardOut,
    MealCardTopUp,
    MealCardTransactionOut,
)

router = APIRouter(prefix="/meal-card", tags=["meal-card"])


@router.post("", response_model=MealCardOut, status_code=status.HTTP_201_CREATED)
async def create_meal_card(
    payload: MealCardCreate, user_id: CurrentUserId, db: DbSession
) -> MealCardOut:
    """Create the current month's meal card if missing, else return existing."""
    return await meal_card_flow.get_or_create_current(
        db=db, user_id=user_id, monthly_budget_eur=payload.monthly_budget_eur
    )


@router.get("/current", response_model=MealCardOut)
async def get_current_meal_card(
    user_id: CurrentUserId, db: DbSession
) -> MealCardOut:
    card = await meal_card_flow.get_current(db=db, user_id=user_id)
    if card is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="no active meal card for the current month",
        )
    return card


@router.post("/topup", response_model=MealCardOut)
async def topup_meal_card(
    payload: MealCardTopUp, user_id: CurrentUserId, db: DbSession
) -> MealCardOut:
    return await meal_card_flow.topup(
        db=db, user_id=user_id, amount_eur=payload.amount_eur
    )


@router.get("/transactions", response_model=list[MealCardTransactionOut])
async def list_meal_card_transactions(
    user_id: CurrentUserId,
    db: DbSession,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[MealCardTransactionOut]:
    return await meal_card_flow.list_transactions(
        db=db, user_id=user_id, limit=limit
    )
