#!/bin/bash

# Step 1: Get the access token
ACCESS_TOKEN=$(curl -s -X POST \
  https://login.microsoftonline.com/botframework.com/oauth2/v2.0/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=2d860c28-09dd-4019-a296-c65062aecb37&client_secret=45711770c8c4949a8c9299b76cf5cdfe449a7a1a8cb82c3342a2682fcae565792e084243c9da68c14e236fac32292789c0088ebb19aeb0899036d02d09c516695dce89ce6dc1d5651602c886159a19400f01e073742cc4680bc2a8d5ce8e42032c5bd05d836733ee6c59ce390231907f52e06ec852e886adf87c1aa418daa270caa62e51b06d31a9&scope=https://api.botframework.com/.default" | jq -r '.access_token')

# Step 2: Test the bot endpoint
curl -X POST \
  https://bot761d5b.azurewebsites.net/api/messages \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "message",
    "from": {
        "id": "user1"
    },
    "conversation": {
        "id": "conv1"
    },
    "recipient": {
        "id": "bot761d5b"
    },
    "text": "Hello, bot!"
}'
