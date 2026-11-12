#!/bin/sh
# Sets up the IAM roles the platform's Amazon CloudWatch integration needs, in the AWS
# account this runs in, as one CloudFormation stack (monitor-cloudwatch-role.yaml).
# Run it once per AWS account, in AWS CloudShell:
#
#   curl -fsSL https://raw.githubusercontent.com/cipherops-io/rtifact-alert-rules/main/setup/cloudwatch/setup-role.sh | sh -s -- <platform_role_arn> <external_id>
#
# Both values come from the platform at onboarding. The script prints the AWS Account ID to
# enter in the platform's Amazon CloudWatch connection (method: Assume Role (single account)).
# The role works in every Region, so the script runs once per account; for many accounts,
# deploy the same template as the StackSet monitor-cloudwatch instead (see the setup guide).
# Running it again is safe.

set -eu
# The script itself arrives on stdin, so nothing may wait on a pager or prompt.
export AWS_PAGER=""

TEMPLATE_URL="https://raw.githubusercontent.com/cipherops-io/rtifact-alert-rules/main/setup/cloudwatch/monitor-cloudwatch-role.yaml"
STACK_NAME="monitor-cloudwatch"
ROLE_NAME="MonitorCloudWatchRole"
INVOKE_ROLE_NAME="MonitorEventBridgeInvokeRole"

fail() {
  echo "" >&2
  echo "ERROR: $*" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  echo "Usage: sh setup-role.sh <platform_role_arn> <external_id>"
  echo "Example: sh setup-role.sh arn:aws:iam::111122223333:role/platform-role 65f0a1b2c3d4e5f6a7b8c9d0"
  echo "The platform gives you both values at onboarding."
  exit 1
fi
PLATFORM_ROLE_ARN="$1"
EXTERNAL_ID="$2"
case "$PLATFORM_ROLE_ARN" in
  arn:aws*:iam::[0-9]*:role/?*) ;;
  *) fail "\"$PLATFORM_ROLE_ARN\" is not an IAM role ARN. Use the platform role ARN the platform gave you, for example arn:aws:iam::111122223333:role/platform-role." ;;
esac
if [ "${#EXTERNAL_ID}" -lt 2 ] || [ "${#EXTERNAL_ID}" -gt 1224 ] ||
  ! printf '%s\n' "$EXTERNAL_ID" | grep -Eq '^[A-Za-z0-9_+=,.@:/-]+$'; then
  fail "\"$EXTERNAL_ID\" is not a valid External ID. Use the External ID the platform gave you."
fi

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [ -z "$REGION" ]; then
  REGION="$(aws configure get region 2>/dev/null || true)"
fi
[ -n "$REGION" ] || fail "Could not tell which AWS Region this runs in. Open CloudShell from the AWS Console."

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" ||
  fail "The AWS CLI is not signed in. Run this in AWS CloudShell."

done_message() {
  cat <<EOF

==================================================================
 Done. In the platform, create an Amazon CloudWatch connection
 with the method "Assume Role (single account)" and enter:

   AWS Account ID:  $ACCOUNT_ID
   AWS Region:      a Region with resources to monitor, e.g. $REGION

 The role works in every Region: add one connection for each
 Region of this account that you want to monitor.
==================================================================
EOF
  PLATFORM_ACCOUNT_ID="$(echo "$PLATFORM_ROLE_ARN" | cut -d: -f5)"
  if [ "$PLATFORM_ACCOUNT_ID" != "$ACCOUNT_ID" ]; then
    cat <<EOF

 The platform runs in another AWS account ($PLATFORM_ACCOUNT_ID). Its role
 must be allowed to assume $ROLE_NAME in this account (setup guide:
 "If the platform runs in another AWS account").
EOF
  fi
}

stack_value() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
    --query "$1" --output text
}

STATUS="$(stack_value 'Stacks[0].StackStatus' 2>/dev/null || true)"
case "$STATUS" in
  "") ;;
  ROLLBACK_COMPLETE)
    # A first attempt that failed leaves an empty stack that cannot be updated.
    echo "Removing stack $STACK_NAME left by an earlier failed attempt..."
    aws cloudformation delete-stack --region "$REGION" --stack-name "$STACK_NAME"
    aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$STACK_NAME"
    STATUS="" ;;
  *_IN_PROGRESS)
    fail "Stack $STACK_NAME is busy ($STATUS). Wait until it finishes, then run this again." ;;
  *_FAILED)
    fail "Stack $STACK_NAME is in state $STATUS. Fix or delete it in the CloudFormation console, then run this again." ;;
esac

if [ -z "$STATUS" ]; then
  if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    # Created by a StackSet, by this script in another Region, or by hand. IAM is
    # global, so it already serves every Region if it trusts the platform correctly.
    TRUST="$(aws iam get-role --role-name "$ROLE_NAME" --query Role.AssumeRolePolicyDocument --output json)"
    case "$TRUST" in
      *"\"$PLATFORM_ROLE_ARN\""*) TRUSTS_PLATFORM=true ;;
      *) TRUSTS_PLATFORM=false ;;
    esac
    case "$TRUST" in
      *"\"$EXTERNAL_ID\""*) TRUSTS_EXTERNAL_ID=true ;;
      *) TRUSTS_EXTERNAL_ID=false ;;
    esac
    if [ "$TRUSTS_PLATFORM" = true ] && [ "$TRUSTS_EXTERNAL_ID" = true ]; then
      echo "$ROLE_NAME already exists in account $ACCOUNT_ID and trusts the platform; nothing to change."
      done_message
      exit 0
    fi
    fail "IAM role $ROLE_NAME already exists in account $ACCOUNT_ID, but its trust policy does not allow $PLATFORM_ROLE_ARN with External ID $EXTERNAL_ID. If a stack in another Region created it, run this command in that Region. If a StackSet created it, update the StackSet's parameters. If it was created by hand, delete it and run this again."
  fi
  CREATE_INVOKE_ROLE=true
  if aws iam get-role --role-name "$INVOKE_ROLE_NAME" >/dev/null 2>&1; then
    CREATE_INVOKE_ROLE=false
    echo "$INVOKE_ROLE_NAME already exists in this account; keeping it."
  fi
  REGION_SCOPE='*'
  echo "Creating stack $STACK_NAME in $REGION (account $ACCOUNT_ID)..."
else
  # Keep what the stack was created with; the External ID is the one given now. The roles are
# always created by this stack, in this Region (RoleRegion below).
  OLD_EXTERNAL_ID="$(stack_value "Stacks[0].Parameters[?ParameterKey=='ExternalId'].ParameterValue")"
  CREATE_INVOKE_ROLE="$(stack_value "Stacks[0].Parameters[?ParameterKey=='CreateInvokeRole'].ParameterValue")"
  REGION_SCOPE="$(stack_value "Stacks[0].Parameters[?ParameterKey=='RegionScope'].ParameterValue")"
  if [ "$OLD_EXTERNAL_ID" != "$EXTERNAL_ID" ]; then
    echo "The role's External ID changes from $OLD_EXTERNAL_ID to $EXTERNAL_ID."
  fi
  echo "Updating stack $STACK_NAME in $REGION (account $ACCOUNT_ID)..."
fi

TEMPLATE_FILE="${TMPDIR:-/tmp}/monitor-cloudwatch-$$.yaml"
trap 'rm -f "$TEMPLATE_FILE"' EXIT
curl -fsSL "$TEMPLATE_URL" -o "$TEMPLATE_FILE" ||
  fail "Could not download the CloudFormation template from $TEMPLATE_URL."

if ! aws cloudformation deploy --region "$REGION" --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_FILE" --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides "PlatformRoleArn=$PLATFORM_ROLE_ARN" "ExternalId=$EXTERNAL_ID" \
  "CreateInvokeRole=$CREATE_INVOKE_ROLE" "RegionScope=$REGION_SCOPE" "RoleRegion=$REGION"; then
  echo "" >&2
  echo "Why it failed:" >&2
  aws cloudformation describe-stack-events --region "$REGION" --stack-name "$STACK_NAME" \
    --query "StackEvents[?contains(ResourceStatus, 'FAILED')].[LogicalResourceId, ResourceStatusReason]" \
    --output text 2>/dev/null | head -5 >&2 || true
  fail "The stack was not deployed. Fix the cause above, then run the same command again."
fi

done_message
