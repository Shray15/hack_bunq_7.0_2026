import os
import json
import boto3
from dotenv import load_dotenv

load_dotenv()

def get_client():
    return boto3.client(
        service_name="bedrock-runtime",
        region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"),
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY"),
        aws_session_token=os.getenv("AWS_SESSION_TOKEN"),
    )

def invoke(prompt: str, model_id: str = None) -> str:
    client = get_client()
    model_id = model_id or os.getenv("AWS_BEDROCK_MODEL_ID", "anthropic.claude-sonnet-4-5")

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}],
    })

    response = client.invoke_model(
        modelId=model_id,
        body=body,
        contentType="application/json",
        accept="application/json",
    )

    result = json.loads(response["body"].read())
    return result["content"][0]["text"]


if _name_ == "_main_":
    print(invoke("Say Culture of Pakistan and Srilanka in one sentence."))