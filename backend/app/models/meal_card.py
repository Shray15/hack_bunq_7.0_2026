from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Float, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAt, UuidPK


class MealCard(Base):
    __tablename__ = "meal_cards"
    __table_args__ = (
        UniqueConstraint("owner_id", "month_year", name="uq_meal_cards_owner_month"),
    )

    id: Mapped[UuidPK]
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    bunq_monetary_account_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    bunq_card_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    iban: Mapped[str] = mapped_column(String(64), nullable=False)
    last_4: Mapped[str | None] = mapped_column(String(8), nullable=True)
    monthly_budget_eur: Mapped[float] = mapped_column(Float, nullable=False)
    current_balance_eur: Mapped[float] = mapped_column(Float, nullable=False)
    month_year: Mapped[str] = mapped_column(String(7), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="active")
    created_at: Mapped[CreatedAt]
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
