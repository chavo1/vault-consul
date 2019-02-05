# This repo contains an example of how to encrypt Consul cluster communications with TLS and it is for learning purpose.

## The certificates are requested from [Vault](https://www.vaultproject.io/) over HTTPS.

### The steps from [Vault](https://learn.hashicorp.com/vault/secrets-management/sm-pki-engine) side are:
- Enable [Vault PKI secrets engine](https://www.vaultproject.io/docs/secrets/pki/index.html)
- Generate Root CA
- Generate Intermediate CA
- Create a Role
### Now we are ready to request the certificates from [Consul](https://www.consul.io/)
- When each consul agent is spined up, it will request a certificate from Vault.
- The certificate are intended for servers or for clients.

### Gossip Encryption for the network traffic
- You only need to set an encryption key when starting the Consul agents.

#### How to use it:

- You need [Vagrant](https://www.vagrantup.com/)
- Clone the repo
- Go to the vault-consul directory
```
$ git clone https://github.com/chavo1/vault-consul.git
$ cd vault-consul
$ vagrant up
```
- This will spin up 1 Vault server, Consul cluster with 3 servers and 2 agents.
- Communication between agent should be encrypted.


