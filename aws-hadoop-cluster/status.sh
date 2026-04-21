#!/bin/bash
# Show current state of the Hadoop cluster EC2 instances.
# Reads cluster-state.env written by deploy.sh.

STATE_FILE="$(dirname "$0")/cluster-state.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
die() { echo -e "${RED}[error]${NC} $1"; exit 1; }

[ -f "$STATE_FILE" ] || die "cluster-state.env not found. Has the cluster been deployed?"

# shellcheck source=/dev/null
source "$STATE_FILE"

get_state() {
    aws ec2 describe-instances \
        --instance-ids "$1" \
        --region "$REGION" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text 2>/dev/null || echo "unknown"
}

get_public_ip() {
    aws ec2 describe-instances \
        --instance-ids "$1" \
        --region "$REGION" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text 2>/dev/null || echo "N/A"
}

NN_STATE=$(get_state  "$NN_INSTANCE_ID")
DN1_STATE=$(get_state "$DN1_INSTANCE_ID")
DN2_STATE=$(get_state "$DN2_INSTANCE_ID")

NN_IP=$(get_public_ip  "$NN_INSTANCE_ID")
DN1_IP=$(get_public_ip "$DN1_INSTANCE_ID")
DN2_IP=$(get_public_ip "$DN2_INSTANCE_ID")

color_state() {
    case "$1" in
        running)   echo -e "${GREEN}$1${NC}" ;;
        stopped)   echo -e "${YELLOW}$1${NC}" ;;
        terminated) echo -e "${RED}$1${NC}" ;;
        *)         echo "$1" ;;
    esac
}

echo ""
echo "========================================================"
echo "  HADOOP CLUSTER STATUS  (region: $REGION)"
echo "========================================================"
echo ""
printf "  %-12s %-22s %-15s %s\n" "ROLE" "INSTANCE ID" "STATE" "PUBLIC IP"
printf "  %-12s %-22s %-15s %s\n" "NameNode"   "$NN_INSTANCE_ID"  "$(color_state "$NN_STATE")"  "$NN_IP"
printf "  %-12s %-22s %-15s %s\n" "DataNode 1" "$DN1_INSTANCE_ID" "$(color_state "$DN1_STATE")" "$DN1_IP"
printf "  %-12s %-22s %-15s %s\n" "DataNode 2" "$DN2_INSTANCE_ID" "$(color_state "$DN2_STATE")" "$DN2_IP"
echo ""

if [ "$NN_STATE" = "running" ]; then
    echo "  NameNode Web UI:  http://${NN_IP}:9870"
    echo "  DataNode 1 UI:    http://${DN1_IP}:9864"
    echo "  DataNode 2 UI:    http://${DN2_IP}:9865"
    echo ""
    echo "  SSH NameNode:    ssh -i $KEY_FILE ubuntu@${NN_IP}"
    echo "  SSH DataNode 1:  ssh -i $KEY_FILE ubuntu@${DN1_IP}"
    echo "  SSH DataNode 2:  ssh -i $KEY_FILE ubuntu@${DN2_IP}"
fi
echo "========================================================"
