from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from app.dependencies import CurrentUser, DbSession
from app.models import Profile as ProfileModel
from app.schemas import Profile, ProfileUpdate

router = APIRouter(prefix="/user", tags=["user"])


@router.get("/profile", response_model=Profile)
async def get_profile(user: CurrentUser) -> Profile:
    if user.profile is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="profile missing")
    return Profile.model_validate(user.profile)


@router.patch("/profile", response_model=Profile)
async def update_profile(payload: ProfileUpdate, user: CurrentUser, db: DbSession) -> Profile:
    result = await db.execute(select(ProfileModel).where(ProfileModel.user_id == user.id))
    profile = result.scalar_one_or_none()
    if profile is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="profile missing")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(profile, field, value)
    await db.commit()
    await db.refresh(profile)
    return Profile.model_validate(profile)
