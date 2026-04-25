from __future__ import annotations

import uuid

from sqlalchemy import Boolean, Float, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAt, UuidPK


class MealShare(Base):
    """Post-checkout 'split the cost' link.

    Created after an order is paid: we mint a fixed-amount bunq.me URL via
    the existing MCP payment infrastructure (per-person share, not the full
    total) and store it here so the user can re-open the same link later
    instead of generating a new one each time."""

    __tablename__ = "meal_shares"

    id: Mapped[UuidPK]
    order_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("orders.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    participant_count: Mapped[int] = mapped_column(Integer, nullable=False)
    include_self: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    per_person_eur: Mapped[float] = mapped_column(Float, nullable=False)
    total_eur: Mapped[float] = mapped_column(Float, nullable=False)
    bunq_request_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    share_url: Mapped[str] = mapped_column(String(2048), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="open")
    created_at: Mapped[CreatedAt]
