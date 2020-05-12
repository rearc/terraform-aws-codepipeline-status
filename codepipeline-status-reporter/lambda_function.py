import boto3
import json
import urllib3
import os
import jwt
import time

github_auth_type = os.environ['GITHUB_AUTH_TYPE']
github_parameter = os.environ['GITHUB_PARAMETER']
github_app_id = os.environ['GITHUB_APP_ID']
github_app_install_id = os.environ['GITHUB_APP_INSTALL_ID']
branch_whitelist = os.environ['BRANCH_WHITELIST']
github_base = "https://api.github.com"

# Returns a temporary access token for GitHub App
def get_access_token(secret_value: str):
    iat = int(time.time())
    exp = iat + 600
    encoded_jwt = jwt.encode({'iat': iat, 'exp': exp, 'iss': github_app_id}, token, algorithm='RS256')
    github_access_token_url = github_base + "/app/installations/{github_app_install_id}/access_tokens"
    url = github_access_token_url.format(github_app_install_id=github_app_install_id)
    headers = {
        "Accept": "application/vnd.github.machine-man-preview+json",
        "User-Agent": "codepipeline-status-reporter",
        "Authorization": "Bearer "+ encoded_jwt.decode('utf-8')
    }
    response = urllib3.PoolManager().request('POST', url, headers=headers)
    return json.loads(response.data)["token"]

def construct_payload(pipeline_name: str, pipeline_state: str, pipeline_stage: str):
    payload = {
        "state": "error",
        "context": "default"
    }
    codepipeline_url = "https://{region}.console.aws.amazon.com/codepipeline/home?region={region}#/view/{pipeline_name}"
    payload["context"] = pipeline_stage
    payload["target_url"] = codepipeline_url.format(region="us-east-1",pipeline_name=pipeline_name)
    if pipeline_state == "STARTED":
        payload["state"] = "pending"
        payload["description"] = "Running " + pipeline_stage
    if pipeline_state == "FAILED":
        payload["state"] = "failure"
        payload["description"] = "Failed to run " + pipeline_stage
    if pipeline_state == "SUCCEEDED":
        payload["state"] = "success"
        payload["description"] = "Successfully ran " + pipeline_stage
    return payload

def handler(event: dict, context: dict):
    print(event)
    # Extract relevant details from event
    region = event["region"]
    pipeline_name = event["detail"]["pipeline"]
    pipeline_state = event["detail"]["state"]
    pipeline_stage = event["detail"]["stage"]
    execution_id = event["detail"]["execution-id"]
    
    # Derive owner, repository, branch, and revision from CodePipeline API
    codepipeline = boto3.client('codepipeline')
    pipeline = codepipeline.get_pipeline(name=pipeline_name)["pipeline"]
    configuration = pipeline["stages"][0]["actions"][0]["configuration"]   
    owner = configuration["Owner"]
    repo = configuration["Repo"]
    branch = configuration["Branch"]
    
    # Discard non-whitelisted branches if set
    if branch_whitelist:
        print("Branch whitelist: " + branch_whitelist)
        whitelisted_branches = branch_whitelist.split(",")
        if (repo + "/" + branch) not in whitelisted_branches:
            print("Discarding non-whitelisted branch event for " + repo + "/" + branch)
            return
    
    # Discard Source stage events
    if pipeline_stage == "Source":
        print("Discarding Source stage events")
        return
    
    # Get revision sha from CodePipeline API
    pipeline_execution = codepipeline.get_pipeline_execution(
        pipelineName=pipeline_name, pipelineExecutionId=execution_id
    )["pipelineExecution"]
    revision = pipeline_execution["artifactRevisions"][0]
    revision_url = revision["revisionUrl"]
    # revision_url has the format https://github.com/:owner/:repo/commit/:sha
    sha = revision_url.rsplit("/",4)[4]

    ssm = boto3.client('ssm')
    response = ssm.get_parameter(Name=github_parameter,WithDecryption=True)
    secret_value = response["Parameter"]["Value"]

    if github_auth_type == "GitHub App":
        token = get_access_token(secret_value)
    else:
        token = secret_value
        
    github_status_url = github_base + "/repos/{owner}/{repo}/statuses/{sha}"
    url = github_status_url.format(owner=owner, repo=repo, sha=sha)
    payload = construct_payload(pipeline_name, pipeline_state, pipeline_stage)
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "codepipeline-status-reporter",
        "Authorization": "token "+ token
    }
    encoded_payload = json.dumps(payload)
    response = urllib3.PoolManager().request('POST', url, body=encoded_payload, headers=headers)