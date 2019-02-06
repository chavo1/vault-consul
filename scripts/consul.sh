#!/usr/bin/env bash

SERVER_COUNT=${SERVER_COUNT}
CONSUL_VERSION=${CONSUL_VERSION}
DCNAME=${DCNAME}
DOMAIN=${DOMAIN}
VAULT_TOKEN=`cat /vagrant/token/keys.txt | grep "Initial Root Token:" | cut -c21-` # Vault token, it is needed to access vault
IPs=$(hostname -I | cut -f2 -d' ')
HOST=$(hostname)
httpUrl="https://192.168.56.71:8200/v1/pki_int/issue/example-dot-com" # Vault address, from where the certificates will be acquired
VaultunSeal="https://192.168.56.71:8200/v1/sys/unseal" # Curl url to unseal Vault
VaultSeal="https://192.168.56.71:8200/v1/sys/seal" # Curl url to seal Vault
key0=`cat /vagrant/token/keys.txt | grep "Unseal Key 1:" | cut -c15-` #
key1=`cat /vagrant/token/keys.txt | grep "Unseal Key 2:" | cut -c15-` # Needed keys to unseal Vault
key2=`cat /vagrant/token/keys.txt | grep "Unseal Key 3:" | cut -c15-` #


# Install packages
which unzip socat jq dig route vim curl sshpass &>/dev/null || {
    apt-get update -y
    apt-get install unzip socat net-tools jq dnsutils vim curl sshpass -y 
}

#####################
# Installing consul #
#####################
sudo mkdir -p /vagrant/pkg

which consul || {
    # consul file exist.
    CHECKFILE="/vagrant/pkg/consul_${CONSUL_VERSION}_linux_amd64.zip"
    if [ ! -f "$CHECKFILE" ]; then
        pushd /vagrant/pkg
        wget https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip
        popd
 
    fi
    
    pushd /usr/local/bin/
    unzip /vagrant/pkg/consul_${CONSUL_VERSION}_linux_amd64.zip 
    sudo chmod +x consul
    popd
}

killall consul
sudo mkdir -p /etc/consul.d/ssl/ /vagrant/consul_logs

# Copy the certificate from Vault in order to autorize consul agents to comunicate with Vault
sshpass -p 'vagrant' scp -o StrictHostKeyChecking=no vagrant@192.168.56.71:"/etc/vault.d/vault.crt" /etc/consul.d/ssl/
set -x
############################### We unseal Vault in order to acquire needed certificates
# Triple Loop to Unseal Vault #             It must be done with 3 keys
###############################
        for x in {0..2}; do
            echo $x
            for u in {0..2}; do
                ukey=key${x}
                `curl --cacert /etc/consul.d/ssl/vault.crt --header --request PUT --data '{"key": "'${!ukey}'"}' $VaultunSeal`
            done
        done
    

##########################
# Starting consul agents # Setting the needed variables for consul server or client
##########################
sudo mkdir -p /etc/consul.d/ssl/

    pushd /etc/consul.d/ssl/
 
        if [[ $HOST =~ consul-server ]]; then
            export bootstrap="\"bootstrap_expect\": $SERVER_COUNT,"  s=true i=server
        else
            export bootstrap="" s=false i=client
        fi

######################################
# Acquiring a Certificate from Vault #
######################################
        GENCERT=`curl --cacert /etc/consul.d/ssl/vault.crt --header "X-Vault-Token: ${VAULT_TOKEN}" --request POST --data '{"common_name": "'${i}.${DCNAME}.${DOMAIN}'", "ttl": "24h", "alt_names": "localhost", "ip_sans": "127.0.0.1"}' $httpUrl`
            if [ $? -ne 0 ]; then
                echo "Vault is not available. Exit ..."
                exit 1 # if vault is not available script will be terminated
            else
                echo $GENCERT | jq -r .data.issuing_ca > consul-agent-ca.pem
                echo $GENCERT | jq -r .data.certificate > consul-agent.pem
                echo $GENCERT | jq -r .data.private_key > consul-agent.key
            fi

    popd

# Sealing Vault /// We duing this for security reason
curl --cacert /etc/consul.d/ssl/vault.crt --header "X-Vault-Token: ${VAULT_TOKEN}" --request PUT $VaultSeal

############################## Gossip encryption is secured with a symmetric key,
# Enabling gossip encryption #    since gossip between nodes is done over UDP.
##############################  https://learn.hashicorp.com/consul/advanced/day-1-operations/agent-encryption#enable-gossip-encryption-existing-cluster
    if [ $HOST == consul-server01 ]; then
        crypto=`consul keygen` # Generate an encryption key only for first node
sudo cat <<EOF > /etc/consul.d/ssl/encrypt.json
{"encrypt": "${crypto}"}
EOF
    else # Copying the key from first node to the other agents
        sshpass -p 'vagrant' scp -o StrictHostKeyChecking=no vagrant@192.168.56.51:"/etc/consul.d/ssl/encrypt.json" /etc/consul.d/ssl/
    fi

######################## 
# Creating consul user # 
########################
sudo groupadd --system consul
sudo useradd -s /sbin/nologin --system -g consul consul
sudo mkdir -p /var/lib/consul
sudo chown -R consul:consul /var/lib/consul
sudo chmod -R 775 /var/lib/consul
sudo chown -R consul:consul /etc/consul.d/ssl


########################
# Adding consul config #
########################
sudo cat << EOF > /etc/consul.d/ssl/config.json
{
    "server": ${s},
    "node_name": "${HOST}",
    "data_dir": "/var/lib/consul",
    "bind_addr": "0.0.0.0",
    "client_addr": "0.0.0.0",
    "ui": true,
    "advertise_addr": "${IPs}",
    ${bootstrap}
    "retry_join": ["192.168.56.51", "192.168.56.52"],
    "verify_outgoing": true,
    "verify_server_hostname": true,
    "verify_incoming_https": false,
    "verify_incoming_rpc": true, 
    "domain": "${DOMAIN}",
    "datacenter": "${DCNAME}",
    "ca_file": "/etc/consul.d/ssl/consul-agent-ca.pem",  
    "cert_file": "/etc/consul.d/ssl/consul-agent.pem",
    "key_file": "/etc/consul.d/ssl/consul-agent.key",
    "ports": {
    "http": -1,
    "https": 8501
  }
}
EOF

####################################
# Consul Server systemd Unit file  #
####################################
sudo cat <<EOF > /etc/systemd/system/consul.service
### BEGIN INIT INFO
# Provides:          consul
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Consul agent
# Description:       Consul service discovery framework
### END INIT INFO

[Unit]
Description=Consul server agent
Requires=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
PIDFile=/var/run/consul/consul.pid
PermissionsStartOnly=true
ExecStartPre=-/bin/mkdir -p /var/run/consul
ExecStartPre=/bin/chown -R consul:consul /var/run/consul
ExecStart=/usr/local/bin/consul agent \
    -config-dir=/etc/consul.d/ssl/ \
    -pid-file=/var/run/consul/consul.pid
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target

EOF

###################
# Starting Consul #
###################

sudo systemctl daemon-reload
sudo systemctl start consul

###########################
# Redirecting conslul log #
###########################
    if [ -d /vagrant ]; then
        mkdir -p /vagrant/consul_logs
        journalctl -f -u consul.service > /vagrant/consul_logs/${HOST}.log &
    else
        journalctl -f -u consul.service > /tmp/consul.log
    fi
echo consul started


set +x
sleep 5

########################
# Check Consul members #
########################
consul members -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem \
-client-key=/etc/consul.d/ssl/consul-agent.key -http-addr="https://127.0.0.1:8501"