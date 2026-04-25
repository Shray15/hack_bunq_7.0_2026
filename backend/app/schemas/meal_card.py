from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import AppModel

MealCardStatus = Literal["active", "expired", "cancelled"]


class MealCardOut(AppModel):
    id: uuid.UUID
    month_year: str
    monthly_budget_eur: float
    current_balance_eur: float
    last_4: str | None
    iban: str
    status: MealCardStatus
    expires_at: datetime
    created_at: datetime


class MealCardCreate(AppModel):
    monthly_budget_eur: float = Field(gt=0, le=10_000)


class MealCardTopUp(AppModel):
    amount_eur: float = Field(gt=0, le=10_000)


class MealCardTransactionOut(AppModel):
    id: str
    amount_eur: float
    description: str
    created_at: datetime | None
