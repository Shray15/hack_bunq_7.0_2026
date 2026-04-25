from app.schemas.common import AppModel


class Profile(AppModel):
    diet: str | None = None
    allergies: list[str] = []
    daily_calorie_target: int | None = None
    protein_g_target: int | None = None
    carbs_g_target: int | None = None
    fat_g_target: int | None = None
    store_priority: list[str] = ["ah", "picnic"]


class ProfileUpdate(AppModel):
    diet: str | None = None
    allergies: list[str] | None = None
    daily_calorie_target: int | None = None
    protein_g_target: int | None = None
    carbs_g_target: int | None = None
    fat_g_target: int | None = None
    store_priority: list[str] | None = None
