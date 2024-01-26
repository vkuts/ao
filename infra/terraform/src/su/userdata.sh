#!/usr/bin/env bash

set -x

mkdir -p /home/alpine/.ssh

### add public keys here for ssh access
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDlLrOkb6n8oBCkX1uF4P5WZNaWfw0JzvSFwXvUo7vjcabWoGc3FZ6WdHni1za/Z61YxALp9vk5rJsRmEIzcqjqNPUpMyj34YvwkIqdSYJ1uv2Wg4Zh+gblMak8pbVmAlb5v/3LKQz6ltumRZwJ67CJjBXqrYyurmpLx08DiGLLVf/pDfayisKiZ1h+bsbcipWboCfCii7F+G4ivoLKevMkkg3wpvOFqcwxMryq2x4zFxBksaAMDNWvV68AuVEaSYpHHTolIY7+40fk6aS1Z5X8wFmf6XaX8e1LjuVGXY3H4i4NVa/hCrBrrBBT0y6N9MTNoZKNoVx0FRpuGPGUmtrlne41Hbx1X/qUIjhjR6kHPPuGqWzNWC38E2ofIY6o9TQynC9xVt89M5k0nFmcJ2SUZxJoXa1tLG0ImF0mirNRQutV2/nhj6mjrd73OAckFRazHAhkFaYFzAOWdbg8ZGp+k9q2y1JWRfWq2V2ClOLp+iW4DYrzQDVQssM2zTyDLaVBHVUxSb6JPsQnl4jE05uRMGVpQNId6h2DoNN6Z0xdb4j0nYpvDOkDqPU5Y3QAtHbXQs41MB3yfkNFFKtRrcOVJW7Qi+C2DO4U00zuhkmgiiSNdixOKn+dDdc9NZ4OfhOkgqYf8h0cx/nGX+aHcN+mgqMmRpBoFwCMnCtET6GcAw== hlolli@gmail.com' >> /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/alpine/.ssh/authorized_keys
chown alpine:alpine /home/alpine/.ssh/authorized_keys

cd /home/alpine

aws secretsmanager get-secret-value --region us-west-1 --secret-id ao-wallet --query SecretString --output text > .wallet

export SU_WORKER_NUMBER=1

cat <<EOF > /home/alpine/init-su.bash
#!/usr/bin/env bash

export GATEWAY_URL=${gateway_url}
export UPLOAD_NODE_URL=${upload_node_url}
export MODE=su
export SU_WALLET_PATH=/home/alpine/.wallet
export SCHEDULER_LIST_PATH=''

PUBLIC_IP="\$(curl http://checkip.amazonaws.com | tr -d '\n')"

cd /home/alpine

CURRENT_ASSIGNMENT_PATH=/home/alpine/current_assignment.txt

rm -f \$CURRENT_ASSIGNMENT_PATH || true

while true; do
    result=$(aws lambda invoke \\
              --cli-binary-format raw-in-base64-out \\
              --function-name assignment-finder \\
              --region ${region} \\
              --payload="{\"public_ip\": \"\$PUBLIC_IP\"}" \\
              \$CURRENT_ASSIGNMENT_PATH )

    if [[ $result == *"FunctionError"* ]]; then
        echo "Function is busy, retrying..."
        sleep 1  # Wait for 1 second before retrying
    else
        echo "Function invoked successfully."
        break
    fi
done



CURRENT_ASSIGNMENT=\$(cat current_assignment.txt | tr -d '\n')

# Check if the file exists
if [ ! -f "\$CURRENT_ASSIGNMENT_PATH" ]; then
    echo "Error: File does not exist."
    exit 1
fi

# Check if the content is a number
if [[ \$CURRENT_ASSIGNMENT =~ ^[0-9]+$ ]]; then
    echo "The file contains a number."
else
    echo "The file does not contain a number."
    exit 1
fi

echo "Current assignment: \$CURRENT_ASSIGNMENT"

export DATABASE_URL=${postgres_writer_instance}/su\$CURRENT_ASSIGNMENT


cat <<EOF2 > /home/alpine/route53_change.json
{
  "Comment": "Automatic DNS update",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "su\$CURRENT_ASSIGNMENT.ao-testnet.xyz",
        "Type": "A",
        "TTL": 5,
        "ResourceRecords": [
          {
            "Value": "\$PUBLIC_IP"
          }
        ]
      }
    }
  ]
}
EOF2

aws route53 change-resource-record-sets \
  --hosted-zone-id ${hosted_zone_id} \
  --change-batch file:///home/alpine/route53_change.json


/home/alpine/su su ${application_port}

EOF

cat <<EOF > /home/alpine/cleanup-su.bash
#!/usr/bin/env bash

cd /home/alpine

CURRENT_ASSIGNMENT_PATH=/home/alpine/current_assignment.txt

# Check if the file exists
if [ ! -f "\$CURRENT_ASSIGNMENT_PATH" ]; then
    echo "OK: No live assignment found"
    exit 0
fi
CURRENT_ASSIGNMENT=\$(cat current_assignment.txt | tr -d '\n')

# Check if the content is a number
if [[ \$CURRENT_ASSIGNMENT =~ ^[0-9]+$ ]]; then
    echo "The file contains an assignment."
else
    echo "assignment not live"
    exit 0
fi

aws dynamodb update-item \\
    --table-name su-assignments-lock \\
    --key "{\\"AssignmentNumber\\": {\\"N\\": \\"\$CURRENT_ASSIGNMENT\\"}}" \\
    --update-expression "SET public_ip = :val" \\
    --expression-attribute-values '{":val": {"NULL": true}}' \\
    --return-values ALL_NEW || true

EOF

chmod +x /home/alpine/init-su.bash
chmod +x /home/alpine/cleanup-su.bash

cat <<EOF > /etc/init.d/su
#!/sbin/openrc-run

user="root"
group="root"
command="/home/alpine/init-su.bash"
directory="/home/alpine"
command_user="\$${user}:\$${group}"
command_background="yes"
pidfile="/run/\$${RC_SVCNAME}.pid"
output_log="/var/log/\$${RC_SVCNAME}.log"
error_log="\$${output_log}"

depend() {
	use net
}

stop() {
    ebegin "Stopping scheduler unit service"
    /home/alpine/cleanup-su.bash || true
    start-stop-daemon --stop --pidfile \$${pidfile}
    eend $?
}

EOF

chmod +x /etc/init.d/su

rc-service su start