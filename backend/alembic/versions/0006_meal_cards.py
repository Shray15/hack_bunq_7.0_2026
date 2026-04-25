"""meal_cards

Revision ID: 0006
Revises: 0005
Create Date: 2026-04-25

"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "meal_cards",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("bunq_monetary_account_id", sa.BigInteger(), nullable=False),
        sa.Column("bunq_card_id", sa.BigInteger(), nullable=True),
        sa.Column("iban", sa.String(length=64), nullable=False),
        sa.Column("last_4", sa.String(length=8), nullable=True),
        sa.Column("monthly_budget_eur", sa.Float(), nullable=False),
        sa.Column("current_balance_eur", sa.Float(), nullable=False),
        sa.Column("month_year", sa.String(length=7), nullable=False),
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default=sa.text("'active'"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("owner_id", "month_year", name="uq_meal_cards_owner_month"),
    )
    op.create_index("ix_meal_cards_owner", "meal_cards", ["owner_id"])


def downgrade() -> None:
    op.drop_index("ix_meal_cards_owner", table_name="meal_cards")
    op.drop_table("meal_cards")
