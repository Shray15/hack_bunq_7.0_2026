"""recipes table

Revision ID: 0002
Revises: 0001
Create Date: 2026-04-25

"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "recipes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("summary", sa.String(length=1024), nullable=True),
        sa.Column(
            "prep_time_min",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("20"),
        ),
        sa.Column(
            "ingredients",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "steps",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "macros",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "validated_macros",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
        sa.Column("image_url", sa.String(length=2048), nullable=True),
        sa.Column(
            "image_status",
            sa.String(length=16),
            nullable=False,
            server_default=sa.text("'pending'"),
        ),
        sa.Column(
            "source",
            sa.String(length=16),
            nullable=False,
            server_default=sa.text("'chat'"),
        ),
        sa.Column(
            "parent_recipe_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("recipes.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("favorited_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_recipes_owner_created",
        "recipes",
        ["owner_id", sa.text("created_at DESC")],
    )
    op.create_index(
        "ix_recipes_owner_favorited",
        "recipes",
        ["owner_id", sa.text("favorited_at DESC")],
        postgresql_where=sa.text("favorited_at IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_recipes_owner_favorited", table_name="recipes")
    op.drop_index("ix_recipes_owner_created", table_name="recipes")
    op.drop_table("recipes")
