"""carts, cart_items, orders

Revision ID: 0003
Revises: 0002
Create Date: 2026-04-25

"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "carts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "recipe_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("recipes.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default=sa.text("'open'"),
        ),
        sa.Column("selected_store", sa.String(length=16), nullable=True),
        sa.Column(
            "people",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("1"),
        ),
        sa.Column(
            "missing_by_store",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_carts_owner", "carts", ["owner_id"])
    op.create_index("ix_carts_recipe", "carts", ["recipe_id"])

    op.create_table(
        "cart_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "cart_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("carts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("store", sa.String(length=16), nullable=False),
        sa.Column("ingredient_name", sa.String(length=255), nullable=False),
        sa.Column("product_id", sa.String(length=255), nullable=False),
        sa.Column("product_name", sa.String(length=512), nullable=False),
        sa.Column("image_url", sa.String(length=2048), nullable=True),
        sa.Column(
            "qty",
            sa.Float(),
            nullable=False,
            server_default=sa.text("1.0"),
        ),
        sa.Column("unit", sa.String(length=64), nullable=True),
        sa.Column("unit_price_eur", sa.Float(), nullable=False),
        sa.Column("total_price_eur", sa.Float(), nullable=False),
        sa.Column("removed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_cart_items_cart", "cart_items", ["cart_id"])
    op.create_index(
        "ix_cart_items_cart_store",
        "cart_items",
        ["cart_id", "store"],
    )

    op.create_table(
        "orders",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "cart_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("carts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("store", sa.String(length=16), nullable=False),
        sa.Column("total_eur", sa.Float(), nullable=False),
        sa.Column("bunq_request_id", sa.String(length=128), nullable=True),
        sa.Column("bunq_payment_url", sa.String(length=2048), nullable=True),
        sa.Column(
            "status",
            sa.String(length=32),
            nullable=False,
            server_default=sa.text("'ready_to_pay'"),
        ),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("fulfilled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_orders_owner", "orders", ["owner_id"])
    op.create_index("ix_orders_cart", "orders", ["cart_id"])


def downgrade() -> None:
    op.drop_index("ix_orders_cart", table_name="orders")
    op.drop_index("ix_orders_owner", table_name="orders")
    op.drop_table("orders")
    op.drop_index("ix_cart_items_cart_store", table_name="cart_items")
    op.drop_index("ix_cart_items_cart", table_name="cart_items")
    op.drop_table("cart_items")
    op.drop_index("ix_carts_recipe", table_name="carts")
    op.drop_index("ix_carts_owner", table_name="carts")
    op.drop_table("carts")
