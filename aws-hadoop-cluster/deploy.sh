#!/bin/bash
# Deploy a 3-node Hadoop cluster on AWS EC2 using Docker Compose.
# Architecture: 1 NameNode + 2 DataNodes, each on a separate EC2 t3.medium.
# Inter-node communication uses AWS internal DNS (ip-X-X-X-X.ec2.internal).
# All resources are tagged cluster=hadoop-bigdata for easy tracking.
# Resource IDs are saved to cluster-state.env for teardown.sh.

set -e

CLUSTER_NAME="hadoop-bigdata"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
INSTANCE_TYPE="t3.medium"
KEY_NAME="${CLUSTER_NAME}-key"
STATE_FILE="$(dirname "$0")/cluster-state.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[deploy]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
die()  { echo -e "${RED}[error]${NC} $1"; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────

command -v aws >/dev/null 2>&1 || die "aws CLI not found. Install it first."
aws sts get-caller-identity >/dev/null 2>&1   || die "AWS credentials not configured. Run 'aws configure'."

if [ -f "$STATE_FILE" ]; then
    die "cluster-state.env already exists — cluster may already be running.\nRun teardown.sh first, or delete cluster-state.env manually."
fi

log "Deploying Hadoop cluster in region: $REGION"

# ── Key Pair ──────────────────────────────────────────────────────────────────

KEY_FILE="$(dirname "$0")/${KEY_NAME}.pem"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
    warn "Key pair $KEY_NAME already exists in AWS. Using existing one."
    warn "Make sure you have the .pem file at: $KEY_FILE"
else
    log "Creating key pair $KEY_NAME..."
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$REGION" \
        --query "KeyMaterial" \
        --output text > "$KEY_FILE"
    chmod 400 "$KEY_FILE"
    log "Key saved to $KEY_FILE"
fi

# ── AMI (Ubuntu 22.04 LTS, latest) ───────────────────────────────────────────

log "Finding latest Ubuntu 22.04 AMI..."
AMI_ID=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners 099720109477 \
    --filters \
        "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
        "Name=state,Values=available" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text)
log "AMI: $AMI_ID"

# ── VPC ───────────────────────────────────────────────────────────────────────

log "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --region "$REGION" \
    --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support    --region "$REGION"
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="${CLUSTER_NAME}-vpc" Key=cluster,Value="$CLUSTER_NAME" --region "$REGION"
log "VPC: $VPC_ID"

# ── Subnet ────────────────────────────────────────────────────────────────────

SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.1.0/24 \
    --availability-zone "${REGION}a" \
    --region "$REGION" \
    --query "Subnet.SubnetId" --output text)
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region "$REGION"
aws ec2 create-tags --resources "$SUBNET_ID" --tags Key=Name,Value="${CLUSTER_NAME}-subnet" Key=cluster,Value="$CLUSTER_NAME" --region "$REGION"
log "Subnet: $SUBNET_ID"

# ── Internet Gateway ──────────────────────────────────────────────────────────

IGW_ID=$(aws ec2 create-internet-gateway \
    --region "$REGION" \
    --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value="${CLUSTER_NAME}-igw" Key=cluster,Value="$CLUSTER_NAME" --region "$REGION"

RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
    --region "$REGION" \
    --query "RouteTables[0].RouteTableId" --output text)
aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION" >/dev/null
log "Internet Gateway: $IGW_ID"

# ── Security Group ────────────────────────────────────────────────────────────

log "Creating security group..."
SG_ID=$(aws ec2 create-security-group \
    --group-name "${CLUSTER_NAME}-sg" \
    --description "Hadoop BigData cluster security group" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query "GroupId" --output text)
aws ec2 create-tags --resources "$SG_ID" --tags Key=Name,Value="${CLUSTER_NAME}-sg" Key=cluster,Value="$CLUSTER_NAME" --region "$REGION"

# SSH from anywhere
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22    --cidr 0.0.0.0/0  --region "$REGION" >/dev/null
# Hadoop NameNode Web UI
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 9870  --cidr 0.0.0.0/0  --region "$REGION" >/dev/null
# DataNode Web UIs (accessed from outside during demo)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 9864  --cidr 0.0.0.0/0  --region "$REGION" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 9865  --cidr 0.0.0.0/0  --region "$REGION" >/dev/null
# DataNode data transfer port (browser upload redirected here)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 9866  --cidr 0.0.0.0/0  --region "$REGION" >/dev/null
# All intra-cluster traffic (nodes talking to each other)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol all  --port -1   --source-group "$SG_ID" --region "$REGION" >/dev/null
log "Security Group: $SG_ID"

# ── User-Data helpers ─────────────────────────────────────────────────────────

# Common bootstrap: install Docker + Docker Compose v2
DOCKER_BOOTSTRAP=$(cat <<'BOOTSTRAP'
#!/bin/bash
set -e
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker
BOOTSTRAP
)

# ── Launch NameNode ───────────────────────────────────────────────────────────

log "Launching NameNode..."

NAMENODE_USERDATA=$(cat <<USERDATA
${DOCKER_BOOTSTRAP}

# Wait for instance hostname to be available
HOSTNAME=\$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)

mkdir -p /opt/hadoop-cluster
cat > /opt/hadoop-cluster/core-site.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://\${HOSTNAME}:9000</value>
  </property>
  <property>
    <name>hadoop.http.staticuser.user</name>
    <value>hdfs</value>
  </property>
</configuration>
XML

cat > /opt/hadoop-cluster/hdfs-site.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>2</value>
  </property>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>/hadoop/dfs/name</value>
  </property>
  <property>
    <name>dfs.namenode.rpc-bind-host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>dfs.namenode.servicerpc-bind-host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>dfs.namenode.http-bind-host</name>
    <value>0.0.0.0</value>
  </property>
</configuration>
XML

cat > /opt/hadoop-cluster/docker-compose.yml <<COMPOSE
services:
  hadoop-namenode:
    image: apache/hadoop:3
    container_name: hadoop-namenode
    hostname: hadoop-namenode
    user: "0:0"
    environment:
      - HADOOP_HOME=/opt/hadoop
    volumes:
      - /opt/hadoop-cluster/core-site.xml:/opt/hadoop/etc/hadoop/core-site.xml
      - /opt/hadoop-cluster/hdfs-site.xml:/opt/hadoop/etc/hadoop/hdfs-site.xml
      - namenode_data:/hadoop/dfs/name
    ports:
      - "9870:9870"
      - "9000:9000"
    command: >
      bash -c "mkdir -p /hadoop/dfs/name &&
               [ ! -d /hadoop/dfs/name/current ] && hdfs namenode -format -force -nonInteractive ;
               hdfs namenode &
               sleep 15 &&
               hdfs dfs -chmod 777 / &&
               hdfs dfs -mkdir -p /data &&
               hdfs dfs -chmod 777 /data &&
               wait"
volumes:
  namenode_data:
COMPOSE

cd /opt/hadoop-cluster
docker compose up -d
USERDATA
)

NN_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_ID" \
    --security-group-ids "$SG_ID" \
    --user-data "$NAMENODE_USERDATA" \
    --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=${CLUSTER_NAME}-namenode},{Key=cluster,Value=${CLUSTER_NAME}},{Key=role,Value=namenode}]" \
    --region "$REGION" \
    --query "Instances[0].InstanceId" --output text)
log "NameNode instance: $NN_INSTANCE_ID"

# ── Wait for NameNode private DNS ─────────────────────────────────────────────

log "Waiting for NameNode to get private DNS..."
aws ec2 wait instance-running --instance-ids "$NN_INSTANCE_ID" --region "$REGION"

NN_PRIVATE_DNS=$(aws ec2 describe-instances \
    --instance-ids "$NN_INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].PrivateDnsName" --output text)
NN_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$NN_INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
log "NameNode private DNS: $NN_PRIVATE_DNS"
log "NameNode public IP:   $NN_PUBLIC_IP"

# ── Launch DataNodes ──────────────────────────────────────────────────────────

log "Launching DataNode 1..."

make_datanode_userdata() {
    local DN_INDEX=$1
    cat <<USERDATA
${DOCKER_BOOTSTRAP}

mkdir -p /opt/hadoop-cluster
cat > /opt/hadoop-cluster/core-site.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://${NN_PRIVATE_DNS}:9000</value>
  </property>
</configuration>
XML

PUBLIC_IP=\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
cat > /opt/hadoop-cluster/hdfs-site.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>2</value>
  </property>
  <property>
    <name>dfs.datanode.data.dir</name>
    <value>/hadoop/dfs/data</value>
  </property>
  <property>
    <name>dfs.datanode.address</name>
    <value>0.0.0.0:9866</value>
  </property>
  <property>
    <name>dfs.datanode.http.address</name>
    <value>0.0.0.0:9864</value>
  </property>
  <property>
    <name>dfs.datanode.hostname</name>
    <value>\${PUBLIC_IP}</value>
  </property>
  <property>
    <name>dfs.client.use.datanode.hostname</name>
    <value>true</value>
  </property>
</configuration>
XML

cat > /opt/hadoop-cluster/docker-compose.yml <<COMPOSE
services:
  hadoop-datanode:
    image: apache/hadoop:3
    container_name: hadoop-datanode
    user: "0:0"
    environment:
      - HADOOP_HOME=/opt/hadoop
    volumes:
      - /opt/hadoop-cluster/core-site.xml:/opt/hadoop/etc/hadoop/core-site.xml
      - /opt/hadoop-cluster/hdfs-site.xml:/opt/hadoop/etc/hadoop/hdfs-site.xml
      - datanode_data:/hadoop/dfs/data
    ports:
      - "9864:9864"
    command: bash -c "mkdir -p /hadoop/dfs/data && hdfs datanode"
volumes:
  datanode_data:
COMPOSE

cd /opt/hadoop-cluster
docker compose up -d
USERDATA
}

DN1_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_ID" \
    --security-group-ids "$SG_ID" \
    --user-data "$(make_datanode_userdata 4)" \
    --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=${CLUSTER_NAME}-datanode-1},{Key=cluster,Value=${CLUSTER_NAME}},{Key=role,Value=datanode}]" \
    --region "$REGION" \
    --query "Instances[0].InstanceId" --output text)
log "DataNode 1 instance: $DN1_INSTANCE_ID"

log "Launching DataNode 2..."
DN2_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_ID" \
    --security-group-ids "$SG_ID" \
    --user-data "$(make_datanode_userdata 5)" \
    --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=${CLUSTER_NAME}-datanode-2},{Key=cluster,Value=${CLUSTER_NAME}},{Key=role,Value=datanode}]" \
    --region "$REGION" \
    --query "Instances[0].InstanceId" --output text)
log "DataNode 2 instance: $DN2_INSTANCE_ID"

# ── Wait for DataNodes ────────────────────────────────────────────────────────

log "Waiting for DataNodes to start..."
aws ec2 wait instance-running \
    --instance-ids "$DN1_INSTANCE_ID" "$DN2_INSTANCE_ID" \
    --region "$REGION"

DN1_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$DN1_INSTANCE_ID" --region "$REGION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
DN2_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$DN2_INSTANCE_ID" --region "$REGION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

# ── Save state ────────────────────────────────────────────────────────────────

cat > "$STATE_FILE" <<STATE
CLUSTER_NAME=${CLUSTER_NAME}
REGION=${REGION}
KEY_NAME=${KEY_NAME}
KEY_FILE=${KEY_FILE}
VPC_ID=${VPC_ID}
SUBNET_ID=${SUBNET_ID}
IGW_ID=${IGW_ID}
RT_ID=${RT_ID}
SG_ID=${SG_ID}
NN_INSTANCE_ID=${NN_INSTANCE_ID}
DN1_INSTANCE_ID=${DN1_INSTANCE_ID}
DN2_INSTANCE_ID=${DN2_INSTANCE_ID}
NN_PRIVATE_DNS=${NN_PRIVATE_DNS}
NN_PUBLIC_IP=${NN_PUBLIC_IP}
DN1_PUBLIC_IP=${DN1_PUBLIC_IP}
DN2_PUBLIC_IP=${DN2_PUBLIC_IP}
STATE
log "State saved to $STATE_FILE"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  HADOOP CLUSTER DEPLOYED"
echo "========================================================"
echo ""
echo "  NameNode Web UI:  http://${NN_PUBLIC_IP}:9870"
echo "  DataNode 1 UI:    http://${DN1_PUBLIC_IP}:9864"
echo "  DataNode 2 UI:    http://${DN2_PUBLIC_IP}:9864"
echo ""
echo "  SSH NameNode:    ssh -i $KEY_FILE ubuntu@${NN_PUBLIC_IP}"
echo "  SSH DataNode 1:  ssh -i $KEY_FILE ubuntu@${DN1_PUBLIC_IP}"
echo "  SSH DataNode 2:  ssh -i $KEY_FILE ubuntu@${DN2_PUBLIC_IP}"
echo ""
echo "  NOTE: Docker + Hadoop bootstrap runs in the background."
echo "  Wait ~3-5 minutes before the Web UI is reachable."
echo "  Monitor: ssh in and run 'sudo journalctl -u cloud-final -f'"
echo ""
echo "  To tear down: ./teardown.sh"
echo "========================================================"
