# terraform-aws-codepipeline-status

Terraform module to report CodePipeline stage execution status to the GitHub commit status API using a Lambda function and CloudWatch Events.

# Authenticating to GitHub

This module supports authenticating as a GitHub App or with a GitHub personal access token. Most teams should go through the steps below to setup a GitHub App so the integration will continue to work regardless of individuals leaving.

# Creating the GitHub App

In your GitHub organization go to Settings -> GitHub Apps (within Developer settings). Click New GitHub App.

For GitHub App name: ${your organization}-codepipeline (Must be unique.)
Description: This GitHub App updates the commit status when CodePipeline runs.
Homepage: https://github.com/rearc/terraform-aws-codepipeline-status

![Register App](/images/register_app.png)

Uncheck Active under Webhook.

![Webhook Inactive](/images/webhook_inactive.png)

For Repository permissions add Read & write for Commit statuses.

![Status Permissions](/images/status_permissions.png)

Otherwise, leave the defaults and click Create GitHub App.

From the new application's general settings, take note of the App ID, upload a logo that will appear on all the commit statuses and generate a private key that will be used for signing access token requests.

![App ID](/images/app_id.png)

Then go to Install App and Install in your organization. From there take note of the App installation ID which is the number at the end of the URL:

![Installation ID](/images/installation_id.png)

# Adding the key or token to Parameter Store

Login to the AWS Console, go to Systems Manager, go to Parameter Store and click Create parameter.

Name: codepipeline-status-key
Description: GitHub App private key for codepipeline-status-reporter Lambda function
Type: SecureString
Value: Paste the contents of the private key generated for the GitHub App.

![Create Parameter](/images/parameter.png)

Click Create parameter.

With the GitHub App ID, App installation ID, and the name of the parameter for the private key, you have all the input variables necessary to deploy the Terraform module to your account.