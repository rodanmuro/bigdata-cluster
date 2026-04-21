#!/bin/bash
# Terminate all EC2 instances and delete all VPC resources created by deploy.sh.
# Reads cluster-state.env for resource IDs.

set -e

STATE_FILE="$(dirname "$0")/cluster-state.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[teardown]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
die()  { echo -e "${RED}[error]${NC} $1"; exit 1; }

[ -f "$STATE_FILE" ] || die "cluster-state.env not found. Has the cluster been deployed?"

# shellcheck source=/dev/null
source "$STATE_FILE"

echo "========================================================"
echo "  This will permanently delete:"
echo "    Instances: $NN_INSTANCE_ID $DN1_INSTANCE_ID $DN2_INSTANCE_ID"
echo "    VPC:       $VPC_ID"
echo "    Region:    $REGION"
echo "========================================================"
read -r -p "  Type 'yes' to confirm: " CONFIRM
[ "$CONFIRM" = "yes" ] || { warn "Aborted."; exit 0; }

# ── Terminate instances ───────────────────────────────────────────────────────

log "Terminating instances..."
aws ec2 terminate-instances \
    --instance-ids "$NN_INSTANCE_ID" "$DN1_INSTANCE_ID" "$DN2_INSTANCE_ID" \
    --region "$REGION" >/dev/null

log "Waiting for instances to terminate (this takes ~1 minute)..."
aws ec2 wait instance-terminated \
    --instance-ids "$NN_INSTANCE_ID" "$DN1_INSTANCE_ID" "$DN2_INSTANCE_ID" \
    --region "$REGION"
log "Instances terminated."

# ── Delete VPC resources ──────────────────────────────────────────────────────

log "Deleting security group $SG_ID..."
aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION"

log "Detaching and deleting internet gateway $IGW_ID..."
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION"

log "Deleting subnet $SUBNET_ID..."
aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$REGION"

log "Deleting VPC $VPC_ID..."
aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION"

# ── Delete key pair (keep local .pem) ────────────────────────────────────────

log "Deleting key pair $KEY_NAME from AWS..."
aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
rm -f "$KEY_FILE"
log "Local key file $KEY_FILE deleted."

# ── Remove state file ─────────────────────────────────────────────────────────

rm -f "$STATE_FILE"
log "State file removed."

echo ""
echo "========================================================"
echo "  CLUSTER TORN DOWN — all AWS resources deleted."
echo "========================================================"
