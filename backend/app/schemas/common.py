from pydantic import BaseModel, ConfigDict


class AppModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


class Macros(AppModel):
    calories: int
    protein_g: int
    carbs_g: int
    fat_g: int
