from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import AppModel

ShareStatus = Literal["open", "closed"]


class ShareCostCreate(AppModel):
    """`POST /orders/{order_id}/share-cost` request body.

    `participant_count` is the number of OTHER people the user is splitting
    with. `include_self` defaults true, so a meal for 4 people = 1 friend
    (the user) + 3 participants → split four ways."""

    participant_count: int = Field(ge=1, le=10)
    include_self: bool = True


class ShareCostOut(AppModel):
    id: uuid.UUID
    order_id: uuid.UUID
    participant_count: int
    include_self: bool
    per_person_eur: float
    total_eur: float
    share_url: str
    bunq_request_id: str | None
    status: ShareStatus
    created_at: datetime
