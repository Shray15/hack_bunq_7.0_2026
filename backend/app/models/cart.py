from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, CreatedAt, UuidPK


class Cart(Base):
    __tablename__ = "carts"

    id: Mapped[UuidPK]
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    recipe_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("recipes.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="open")
    selected_store: Mapped[str | None] = mapped_column(String(16), nullable=True)
    people: Mapped[int] = mapped_column(Integer, nullable=False, default=1)

    # `missing_by_store`: {"ah": ["parsley"], "picnic": []} — per-store list of
    # ingredient names the MCP couldn't match. iOS uses missing_count for the
    # comparison card; substitution flow (Phase 4) consumes the names.
    missing_by_store: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )
    created_at: Mapped[CreatedAt]

    items: Mapped[list[CartItem]] = relationship(
        back_populates="cart",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class CartItem(Base):
    __tablename__ = "cart_items"

    id: Mapped[UuidPK]
    cart_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("carts.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    store: Mapped[str] = mapped_column(String(16), nullable=False)
    ingredient_name: Mapped[str] = mapped_column(String(255), nullable=False)
    product_id: Mapped[str] = mapped_column(String(255), nullable=False)
    product_name: Mapped[str] = mapped_column(String(512), nullable=False)
    image_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    qty: Mapped[float] = mapped_column(Float, nullable=False, default=1.0)
    unit: Mapped[str | None] = mapped_column(String(64), nullable=True)
    unit_price_eur: Mapped[float] = mapped_column(Float, nullable=False)
    total_price_eur: Mapped[float] = mapped_column(Float, nullable=False)
    removed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    cart: Mapped[Cart] = relationship(back_populates="items")
