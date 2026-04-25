from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAt, UuidPK


class Recipe(Base):
    __tablename__ = "recipes"

    id: Mapped[UuidPK]
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    summary: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    prep_time_min: Mapped[int] = mapped_column(Integer, nullable=False, default=20)

    # Structured payloads, stored as-is so iOS reads them without joins.
    ingredients: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False)
    steps: Mapped[list[str]] = mapped_column(JSONB, nullable=False)
    macros: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    validated_macros: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)

    image_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")

    source: Mapped[str] = mapped_column(String(16), nullable=False, default="chat")
    parent_recipe_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("recipes.id", ondelete="SET NULL"),
        nullable=True,
    )

    favorited_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[CreatedAt]
