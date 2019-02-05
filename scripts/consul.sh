#!/usr/bin/env bash

SERVER_COUNT=${SERVER_COUNT}
CONSUL_VERSION=${CONSUL_VERSION}
DCNAME=${DCNAME}
DOMAIN=${DOMAIN}
VAULT_TOKEN=`cat /vagrant/token/keys.txt | grep "Initial Root Token:" | cut -c21-` # Vault token, it is needed to access vault
IPs=$(hostname -I | cut -f2 -d' ')
HOST=$(hostname)
httpUrl="https://192.168.56.71:8200/v1/pki_int/issue/example-dot-com" # Vault address, from where the certificates will be acquired

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

sshpass -p 'vagrant' scp -o StrictHostKeyChecking=no vagrant@192.168.56.71:"/etc/vault.d/vault.crt" /etc/consul.d/ssl/
set -x

##########################
# Starting consul agents #
##########################
sudo mkdir -p /etc/consul.d/ssl/

    pushd /etc/consul.d/ssl/
 
        if [[ $HOST =~ consul-server ]]; then
            export bootstrap="-bootstrap-expect=$SERVER_COUNT"  s="-server" i=server
        else
            export bootstrap="" s="" i=client
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

##############################
# Enabling gossip encryption #
##############################
    if [ $HOST == consul-server01 ]; then
        crypto=`consul keygen` # generate for first node
sudo cat <<EOF > /etc/consul.d/ssl/encrypt.json
{"encrypt": "${crypto}"}
EOF
    else
        sshpass -p 'vagrant' scp -o StrictHostKeyChecking=no vagrant@192.168.56.51:"/etc/consul.d/ssl/encrypt.json" /etc/consul.d/ssl/
    fi

########################
# Adding consul config #
########################
sudo cat <<EOF > /etc/consul.d/ssl/config.json
{
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

###################
# Starting Consul #
###################
consul agent $s -ui -bind 0.0.0.0 -advertise $IPs -client 0.0.0.0 -data-dir=/tmp/consul \
    $bootstrap -config-dir=/etc/consul.d/ssl/ -retry-join=192.168.56.52 \
    -retry-join=192.168.56.51 > /vagrant/consul_logs/$HOST.log & 

set +x
sleep 5

########################
# Check Consul members #
########################
consul members -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem \
-client-key=/etc/consul.d/ssl/consul-agent.key -http-addr="https://127.0.0.1:8501"