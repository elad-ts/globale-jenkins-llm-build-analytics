FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ARG BEDROCK_AGENT_ID
ARG BEDROCK_AGENT_ALIAS_ID
ENV BEDROCK_AGENT_ID=${BEDROCK_AGENT_ID}
ENV BEDROCK_AGENT_ALIAS_ID=${BEDROCK_AGENT_ALIAS_ID}

# run agent evaluation
# TODO - run all tests
CMD sed -e "s/BEDROCK_AGENT_ALIAS_ID/$BEDROCK_AGENT_ALIAS_ID/g" \
        -e "s/BEDROCK_AGENT_ID/$BEDROCK_AGENT_ID/g" \
        bedrock_agent_evaluation/test_plan_templates/mvn_build_failure.yaml > agenteval.yml \
    && agenteval run
