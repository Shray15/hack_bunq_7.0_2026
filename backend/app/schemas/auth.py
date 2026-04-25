from pydantic import EmailStr, Field

from app.schemas.common import AppModel


class SignupRequest(AppModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(AppModel):
    email: EmailStr
    password: str


class TokenResponse(AppModel):
    access_token: str
    token_type: str = "bearer"
