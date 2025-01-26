def lambda_handler(event, context):
    """
    A simple AWS Lambda function that returns a 200 status code and a message.

    Parameters:
    - event: The event triggering the function.
    - context: Runtime information provided by AWS Lambda.

    Returns:
    - dict: A response with a 200 status code and a message.
    """
    return {
        "statusCode": 200,
        "body": "Hello from AWS Lambda!"
    }
