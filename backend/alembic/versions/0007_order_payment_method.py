"""orders.payment_method + orders.bunq_payment_id

Revision ID: 0007
Revises: 0006
Create Date: 2026-04-25

"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "orders",
        sa.Column(
            "payment_method",
            sa.String(length=16),
            nullable=False,
            server_default=sa.text("'bunq_me'"),
        ),
    )
    op.add_column(
        "orders",
        sa.Column("bunq_payment_id", sa.String(length=128), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("orders", "bunq_payment_id")
    op.drop_column("orders", "payment_method")
