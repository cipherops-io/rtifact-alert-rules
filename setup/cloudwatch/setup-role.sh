#!/bin/sh
# Sets up the IAM roles the platform's Amazon CloudWatch integration needs, in the AWS
# account this runs in, as one CloudFormation stack (monitor-cloudwatch-role.yaml).
# Run it in AWS CloudShell, in the Region you want to monitor:
#
#   curl -fsSL https://raw.githubusercontent.com/cipherops-io/rtifact-alert-rules/main/setup/cloudwatch/setup-role.sh | sh -s -- <platform_role_arn>
#
# It prints the Region, Role ARN and External ID to enter in the platform's Amazon
# CloudWatch connection (method: Assume Role). Running it again updates the same stack and
# keeps its External ID, so an existing connection keeps working.

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

if [ "$#" -ne 1 ]; then
  echo "Usage: sh setup-role.sh <platform_role_arn>"
  echo "Example: sh setup-role.sh arn:aws:iam::111122223333:role/platform-role"
  exit 1
fi
PLATFORM_ROLE_ARN="$1"
case "$PLATFORM_ROLE_ARN" in
  arn:aws*:iam::[0-9]*:role/?*) ;;
  *) fail "\"$PLATFORM_ROLE_ARN\" is not an IAM role ARN. Use the platform role ARN from the setup guide, for example arn:aws:iam::111122223333:role/platform-role." ;;
esac

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [ -z "$REGION" ]; then
  REGION="$(aws configure get region 2>/dev/null || true)"
fi
[ -n "$REGION" ] || fail "Could not tell which AWS Region this runs in. Open CloudShell from the AWS Console in the Region you want to monitor."

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" ||
  fail "The AWS CLI is not signed in. Run this in AWS CloudShell."

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
    fail "IAM role $ROLE_NAME already exists in account $ACCOUNT_ID, but stack $STACK_NAME is not in $REGION. If this script ran before in another Region, run it there. If the role was created by hand, delete it and run this again."
  fi
  EXTERNAL_ID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || true)"
  [ -n "$EXTERNAL_ID" ] || fail "Could not generate an External ID."
  CREATE_INVOKE_ROLE=true
  if aws iam get-role --role-name "$INVOKE_ROLE_NAME" >/dev/null 2>&1; then
    CREATE_INVOKE_ROLE=false
    echo "$INVOKE_ROLE_NAME already exists in this account; keeping it."
  fi
  REGION_SCOPE='*'
  echo "Creating stack $STACK_NAME in $REGION (account $ACCOUNT_ID)..."
else
  # Keep what the stack was created with, above all its External ID.
  EXTERNAL_ID="$(stack_value "Stacks[0].Parameters[?ParameterKey=='ExternalId'].ParameterValue")"
  CREATE_INVOKE_ROLE="$(stack_value "Stacks[0].Parameters[?ParameterKey=='CreateInvokeRole'].ParameterValue")"
  REGION_SCOPE="$(stack_value "Stacks[0].Parameters[?ParameterKey=='RegionScope'].ParameterValue")"
  echo "Updating stack $STACK_NAME in $REGION (account $ACCOUNT_ID); its External ID stays the same..."
fi

TEMPLATE_FILE="${TMPDIR:-/tmp}/monitor-cloudwatch-$$.yaml"
trap 'rm -f "$TEMPLATE_FILE"' EXIT
curl -fsSL "$TEMPLATE_URL" -o "$TEMPLATE_FILE" ||
  fail "Could not download the CloudFormation template from $TEMPLATE_URL."

if ! aws cloudformation deploy --region "$REGION" --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_FILE" --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides "PlatformRoleArn=$PLATFORM_ROLE_ARN" "ExternalId=$EXTERNAL_ID" \
  "CreateInvokeRole=$CREATE_INVOKE_ROLE" "RegionScope=$REGION_SCOPE"; then
  echo "" >&2
  echo "Why it failed:" >&2
  aws cloudformation describe-stack-events --region "$REGION" --stack-name "$STACK_NAME" \
    --query "StackEvents[?contains(ResourceStatus, 'FAILED')].[LogicalResourceId, ResourceStatusReason]" \
    --output text 2>/dev/null | head -5 >&2 || true
  fail "The stack was not deployed. Fix the cause above, then run the same command again."
fi

ROLE_ARN="$(stack_value "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue")"

cat <<EOF

==================================================================
 Done. In the platform, create an Amazon CloudWatch connection
 with the method "Assume Role" and enter:

   AWS Region:   $REGION
   Role ARN:     $ROLE_ARN
   External ID:  $EXTERNAL_ID

 This is the Region CloudShell runs in. To monitor several Regions,
 create one connection per Region with the same Role ARN and
 External ID.
==================================================================
EOF

PLATFORM_ACCOUNT_ID="$(echo "$PLATFORM_ROLE_ARN" | cut -d: -f5)"
if [ "$PLATFORM_ACCOUNT_ID" != "$ACCOUNT_ID" ]; then
  cat <<EOF

 The platform runs in another AWS account ($PLATFORM_ACCOUNT_ID). Ask the team
 that installed it to allow its role to assume $ROLE_ARN
 (setup guide: "If the platform runs in another AWS account").
EOF
fi
