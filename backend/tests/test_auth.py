from httpx import AsyncClient


async def test_signup_login_profile_roundtrip(client: AsyncClient) -> None:
    signup = await client.post(
        "/auth/signup", json={"email": "alice@test.dev", "password": "supersecret"}
    )
    assert signup.status_code == 201, signup.text
    token = signup.json()["access_token"]
    assert token

    login = await client.post(
        "/auth/login", json={"email": "alice@test.dev", "password": "supersecret"}
    )
    assert login.status_code == 200, login.text
    assert login.json()["access_token"]

    headers = {"Authorization": f"Bearer {token}"}
    profile = await client.get("/user/profile", headers=headers)
    assert profile.status_code == 200, profile.text
    body = profile.json()
    assert body["store_priority"] == ["ah", "picnic"]
    assert body["allergies"] == []

    patched = await client.patch(
        "/user/profile",
        headers=headers,
        json={
            "diet": "high-protein",
            "allergies": ["peanut"],
            "daily_calorie_target": 2400,
        },
    )
    assert patched.status_code == 200, patched.text
    out = patched.json()
    assert out["diet"] == "high-protein"
    assert out["allergies"] == ["peanut"]
    assert out["daily_calorie_target"] == 2400


async def test_signup_duplicate_email_409(client: AsyncClient) -> None:
    payload = {"email": "bob@test.dev", "password": "supersecret"}
    r1 = await client.post("/auth/signup", json=payload)
    assert r1.status_code == 201
    r2 = await client.post("/auth/signup", json=payload)
    assert r2.status_code == 409


async def test_login_wrong_password_401(client: AsyncClient) -> None:
    await client.post("/auth/signup", json={"email": "carol@test.dev", "password": "supersecret"})
    bad = await client.post(
        "/auth/login", json={"email": "carol@test.dev", "password": "wrongpass"}
    )
    assert bad.status_code == 401


async def test_profile_requires_auth(client: AsyncClient) -> None:
    resp = await client.get("/user/profile")
    assert resp.status_code == 401
