# Phase 0 Runbook — Provisioning the Backend

This walks you through every manual step to take Phase 0 from a fresh AWS + GitHub account to a live `http://<ec2-ip>:4567/healthz` that auto-deploys on `git push origin main`.

Anything that can be automated already is — this file only contains the steps a script can't do for you.

---

## Prerequisites

- AWS account with billing enabled
- This repo pushed to GitHub (already done: `Shray15/hack_bunq_7.0_2026`)
- `ssh`, `curl` locally

---

## 1. Provision EC2

1. **Launch instance** (any region works for a hackathon):
   - AMI: **Ubuntu 22.04 or 24.04 LTS** (x86_64)
   - Type: `t3.small`
   - Storage: 30 GB `gp3`
   - Key pair: create or reuse a key (you'll use this for the *initial* SSH-in; GHA gets its own deploy key later)
   - Security group:
     - Inbound: **SSH (22)** from your IP, **TCP 4567** from `0.0.0.0/0`
     - Outbound: all
   - Tag: `Name=cooking-backend`
2. **Allocate Elastic IP** and associate it with the instance — keeps the IP stable across reboots.
3. **SSH in:**
   ```sh
   ssh -i ~/.ssh/<your-keypair>.pem ubuntu@<elastic-ip>
   ```
4. **Run the bootstrap script** (installs Docker + compose, creates `/opt/app`, prepares `/data/postgres`):
   ```sh
   curl -fsSL https://raw.githubusercontent.com/Shray15/hack_bunq_7.0_2026/main/deploy/setup-ec2.sh | sudo bash
   # re-login so the docker group membership takes effect
   exit
   ssh -i ~/.ssh/<your-keypair>.pem ubuntu@<elastic-ip>
   docker ps   # should work without sudo
   ```

---

## 2. Generate a deploy SSH key for GitHub Actions

GHA needs its own keypair — do **not** reuse the one you used to SSH in.

On your laptop:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/cooking_deploy_key -N "" -C "gha-deploy"
```

Copy the **public** key to EC2:

```sh
scp -i ~/.ssh/<your-keypair>.pem ~/.ssh/cooking_deploy_key.pub ubuntu@<elastic-ip>:/tmp/
ssh -i ~/.ssh/<your-keypair>.pem ubuntu@<elastic-ip> 'cat /tmp/cooking_deploy_key.pub >> ~/.ssh/authorized_keys && rm /tmp/cooking_deploy_key.pub'
```

Verify:

```sh
ssh -i ~/.ssh/cooking_deploy_key ubuntu@<elastic-ip> 'echo ok'   # → ok
```

The **private** key (`~/.ssh/cooking_deploy_key`) goes into a GitHub secret in step 3.

---

## 3. Enable GHCR for the repo

GitHub Container Registry is enabled implicitly by the workflow (`packages: write` permission). The first successful image push will create the package automatically. Once it exists, go to repo → **Packages** → tap the package → **Package settings** → **Manage Actions access** → ensure this repo has at least `Write` access. (For new repos it's set automatically.)

---

## 4. Set GitHub Actions secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**. Add every row:

| Secret | Value | Notes |
|---|---|---|
| `EC2_HOST` | `<elastic-ip>` or DNS hostname | The host GHA SSHs into and the verify step curls |
| `EC2_USER` | `ubuntu` | Default for Ubuntu AMIs |
| `EC2_SSH_KEY` | contents of `~/.ssh/cooking_deploy_key` | Full private key, including `-----BEGIN`/`-----END` lines |
| `POSTGRES_PASSWORD` | `openssl rand -hex 32` | Generate fresh; never reuse |
| `JWT_SECRET` | `openssl rand -hex 32` | Generate fresh |
| `AWS_ACCESS_KEY_ID` | `AKIA...` | AWS IAM credentials for Bedrock |
| `AWS_SECRET_ACCESS_KEY` | `...` | AWS IAM credentials for Bedrock |
| `AWS_SESSION_TOKEN` | `...` | Only needed for temporary/STS credentials |
| `AWS_DEFAULT_REGION` | `us-east-1` | Bedrock region |
| `AWS_REGION` | `us-east-1` | Same as above |
| `AGENTCORE_MEMORY_ROLE_ARN` | `arn:aws:iam::...` | Role ARN for AgentCore memory |
| `GEMINI_API_KEY` | `AIza...` | From aistudio.google.com (Phase 2) |
| `BUNQ_API_KEY` | sandbox key | Phase 0 placeholder OK; replace before Phase 3 |
| `BUNQ_INSTALLATION_TOKEN` | sandbox token | Same |

> The workflow also reads `GITHUB_TOKEN`, which GitHub provides automatically — don't add it.

---

## 5. Branch protection on `main`

Repo → **Settings → Branches → Add rule** for `main`:

- ✅ Require a pull request before merging
- ✅ Require status checks to pass (you can leave the list empty for Phase 0; Phase 1 adds CI)
- ✅ Require linear history (optional, recommended)
- ❌ Do **not** allow direct pushes to `main`

`workflow_dispatch` from any branch still works — you'll use that to test feature branches on EC2 manually.

---

## 6. First deploy

1. Open a PR with this Phase 0 scaffold (or push directly if branch protection isn't set up yet).
2. Merge the PR → GHA `Deploy` workflow auto-triggers.
3. Watch the workflow in the **Actions** tab. Expected duration: ~2–3 min for the first run (image build), ~60–90 s for subsequent deploys.
4. The final **Verify deployment** step polls `http://<EC2_HOST>:4567/healthz` for up to ~90 s until the new version string appears.

---

## 7. Verify Phase 0 exit criteria

```sh
# 1. /healthz responds directly on port 4567
curl http://<elastic-ip>:4567/healthz
# → {"ok":true,"version":"main-abc1234","environment":"production"}

# 2. Push a trivial change to main → version string changes within ~90 s

# 3. Manual deploy of a feature branch
#   GitHub UI → Actions → Deploy → Run workflow → pick your branch
# After it finishes, /healthz returns the feature branch version.
# Re-running the workflow on main restores it.

# 4. On EC2 itself
ssh -i ~/.ssh/cooking_deploy_key ubuntu@<elastic-ip>
docker compose -f /opt/app/docker-compose.yml ps
# Expected: postgres healthy, backend healthy
```

---

## Troubleshooting

**`/healthz` times out.** Check that port 4567 is open in the EC2 security group (inbound TCP 4567, source 0.0.0.0/0).

**GHA deploy fails at SSH.** `ssh-keyscan` runs in `Configure SSH`; if EC2 IP changed, just re-run the workflow — keyscan re-fetches each time. If `EC2_SSH_KEY` is wrong you'll see `Permission denied (publickey)` — re-paste the private key with no leading/trailing whitespace.

**`docker compose pull` fails with `unauthorized`.** GHA logs in to GHCR with `GITHUB_TOKEN` (1-hour TTL). If the package is `private` and GHA's token lacks access, go to **Package settings** → **Manage Actions access** → add the repo with `Write`.

**Postgres won't start.** Most likely `/data/postgres` doesn't exist or has wrong owner. Re-run `setup-ec2.sh` (idempotent). Check `docker compose logs postgres`.

**`backend` container exits immediately.** `docker compose logs backend` will show why. Phase 0 only depends on `VERSION` and `ENVIRONMENT`, so the most likely cause is a missing image tag. Confirm `cat /opt/app/.env | grep IMAGE` matches a tag that exists in GHCR.
