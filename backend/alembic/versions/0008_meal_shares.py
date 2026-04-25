"""meal_shares

Revision ID: 0008
Revises: 0007
Create Date: 2026-04-25

"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "meal_shares",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "order_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("orders.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("participant_count", sa.Integer(), nullable=False),
        sa.Column(
            "include_self",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column("per_person_eur", sa.Float(), nullable=False),
        sa.Column("total_eur", sa.Float(), nullable=False),
        sa.Column("bunq_request_id", sa.String(length=128), nullable=True),
        sa.Column("share_url", sa.String(length=2048), nullable=False),
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default=sa.text("'open'"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_meal_shares_order", "meal_shares", ["order_id"])
    op.create_index("ix_meal_shares_owner", "meal_shares", ["owner_id"])


def downgrade() -> None:
    op.drop_index("ix_meal_shares_owner", table_name="meal_shares")
    op.drop_index("ix_meal_shares_order", table_name="meal_shares")
    op.drop_table("meal_shares")
