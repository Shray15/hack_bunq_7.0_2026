from __future__ import annotations

import uuid
from typing import TYPE_CHECKING, Any

from sqlalchemy import ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class Profile(Base):
    __tablename__ = "profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    diet: Mapped[str | None] = mapped_column(String(64), nullable=True)
    allergies: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    daily_calorie_target: Mapped[int | None] = mapped_column(Integer, nullable=True)
    protein_g_target: Mapped[int | None] = mapped_column(Integer, nullable=True)
    carbs_g_target: Mapped[int | None] = mapped_column(Integer, nullable=True)
    fat_g_target: Mapped[int | None] = mapped_column(Integer, nullable=True)
    store_priority: Mapped[list[str]] = mapped_column(
        JSONB,
        nullable=False,
        default=lambda: ["ah", "picnic"],
    )
    extra: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)

    user: Mapped[User] = relationship(back_populates="profile")
