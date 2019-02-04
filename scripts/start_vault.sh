#!/usr/bin/env bash

DCNAME=${DCNAME}
DOMAIN=${DOMAIN}

HOST=$(hostname)

if [ -d /vagrant ]; then
  mkdir -p /vagrant/vault_logs
  LOG="/vagrant/vault_logs/vault_${HOST}.log"
else
  LOG="vault.log"
fi

#kill past instance
sudo killall vault &>/dev/null

#delete old token if present
[ -f /root/.vault-token ] && sudo rm /root/.vault-token

#start vault
sudo /usr/local/bin/vault server  -dev -dev-listen-address=0.0.0.0:8200  &> /vagrant/vault_logs/vault_${HOST}.log &
echo vault started
sleep 3 

grep VAULT_ADDR ~/.bashrc || {
  echo export VAULT_ADDR=http://127.0.0.1:8200 | sudo tee -a ~/.bashrc
}

echo "vault token:"
cat /root/.vault-token
echo -e "\nvault token is on /root/.vault-token"
mkdir -p /vagrant/token/
cp /root/.vault-token /vagrant/token/vault-token
  
# enable secret KV version 1
sudo VAULT_ADDR="http://127.0.0.1:8200" vault secrets enable -version=1 kv
  
# setup .bashrc
grep VAULT_TOKEN ~/.bashrc || {
  echo export VAULT_TOKEN=\`cat /root/.vault-token\` | sudo tee -a ~/.bashrc
}

sudo VAULT_ADDR="http://127.0.0.1:8200" vault secrets enable pki
sudo VAULT_ADDR="http://127.0.0.1:8200" vault secrets tune -max-lease-ttl=87600h pki
sudo VAULT_ADDR="http://127.0.0.1:8200" vault write -field=certificate pki/root/generate/internal common_name="example.com" \
      ttl=87600h > CA_cert.crt
sudo VAULT_ADDR="http://127.0.0.1:8200" vault write pki/config/urls \
      issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
      crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
sudo VAULT_ADDR="http://127.0.0.1:8200" vault secrets enable -path=pki_int pki
sudo VAULT_ADDR="http://127.0.0.1:8200" vault secrets tune -max-lease-ttl=43800h pki_int
sudo VAULT_ADDR="http://127.0.0.1:8200" vault write -format=json pki_int/intermediate/generate/internal \
        common_name="example.com Intermediate Authority" ttl="43800h" \
        | jq -r '.data.csr' > pki_intermediate.csr
sudo VAULT_ADDR="http://127.0.0.1:8200" vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
        format=pem_bundle \
        | jq -r '.data.certificate' > intermediate.cert.pem
sudo VAULT_ADDR="http://127.0.0.1:8200" vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem
sudo VAULT_ADDR="http://127.0.0.1:8200" vault write pki_int/roles/example-dot-com \
        allowed_domains="${DCNAME}.${DOMAIN}" \
        allow_subdomains=true \
        max_ttl="720h"
        