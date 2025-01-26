import boto3
import json
import os

# Environment variables
BEARER_TOKEN = os.getenv("BEARER_TOKEN", "your-secure-token")
AGENT_ID = os.getenv("AGENT_ID", "your-agent-id")
AGENT_ALIAS_ID = os.getenv("AGENT_ALIAS_ID", "")  # Optional
PROMPT_IDENTIFIER = os.getenv("PROMPT_IDENTIFIER", "default-prompt")
PROMPT_VERSION = os.getenv("PROMPT_VERSION", "latest")
PROMPT_VERSION = os.getenv("PROMPT_VERSION", "latest")


# Initialize the Bedrock Agent and Runtime clients
bedrock_runtime_client = boto3.client('bedrock-agent-runtime', region_name='us-east-1')
bedrock_client = boto3.client('bedrock', region_name='us-east-1')



def handler(event, context):
    """
    Lambda function handler for interacting with Bedrock Agent.
    """
    try:
        # Validate the Bearer token
        headers = event.get("headers", {})
        auth_header = headers.get("Authorization", "")
        if not auth_header.startswith("Bearer ") or auth_header.split(" ")[1] != BEARER_TOKEN:
            return {"statusCode": 401, "body": json.dumps({"message": "Unauthorized"})}

        # Parse the input body
        body = json.loads(event.get("body", "{}"))
        user_input = body.get("prompt", "Hello!")

        # Retrieve the prompt version and prepare the input text
        prompt_text = retrieve_prompt_text(PROMPT_IDENTIFIER, PROMPT_VERSION)
        full_prompt = f"{prompt_text}\n{user_input}"

        # Invoke the Bedrock Agent
        response = invoke_bedrock_agent(full_prompt)
        return {"statusCode": 200, "body": json.dumps({"response": response})}

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def retrieve_prompt_text(prompt_identifier, version="latest"):
    """
    Retrieve the specified prompt version using the Bedrock Agent API.
    """
    try:
        response = bedrock_client.get_prompt(
            promptIdentifier=prompt_identifier,
            promptVersion=version
        )
        return response.get("promptText", "Default prompt text")
    except Exception as e:
        raise Exception(f"Failed to retrieve prompt '{prompt_identifier}' version '{version}': {str(e)}")


def invoke_bedrock_agent(prompt):
    """
    Invoke the Bedrock Agent using the provided prompt.
    """
    try:
        invoke_params = {
            "agentId": AGENT_ID,
            "sessionId": "session-id",
            "inputText": prompt
        }
        # Include alias ID if available
        if AGENT_ALIAS_ID:
            invoke_params["agentAliasId"] = AGENT_ALIAS_ID

        # Call the Bedrock Agent Runtime API
        response = bedrock_runtime_client.invoke_agent(**invoke_params)
        return response.get("completion", "No response from agent")

    except Exception as e:
        raise Exception(f"Error invoking Bedrock Agent: {str(e)}")
