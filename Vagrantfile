SERVER_COUNT = 3
CLIENT_COUNT = 1
VAULT_COUNT = 1
VAULT_VERSION = '1.0.2'
CONSUL_VERSION = '1.4.2'
DCNAME = 'chavo'
DOMAIN = 'consul'


Vagrant.configure(2) do |config|
    config.vm.box = "chavo1/xenial64base"
    config.vm.provider "virtualbox" do |v|
      v.memory = 512
      v.cpus = 2
    
    end

    1.upto(VAULT_COUNT) do |n|
      config.vm.define "vault0#{n}" do |vault|
        vault.vm.hostname = "vault0#{n}"
        vault.vm.network "private_network", ip: "192.168.56.#{70+n}"
        vault.vm.provision "shell",inline: "cd /vagrant ; bash scripts/install_vault.sh", env: {"VAULT_VERSION" => VAULT_VERSION}
        vault.vm.provision "shell",inline: "cd /vagrant ; bash scripts/start_vault.sh", env: {"DCNAME" => DCNAME, "DOMAIN" => DOMAIN}

      end
    end

    1.upto(SERVER_COUNT) do |n|
      config.vm.define "consul-server0#{n}" do |server|
        server.vm.hostname = "consul-server0#{n}"
        server.vm.network "private_network", ip: "192.168.56.#{50+n}"
        server.vm.provision "shell",inline: "cd /vagrant ; bash scripts/consul.sh", env: {"CONSUL_VERSION" => CONSUL_VERSION, "SERVER_COUNT" => SERVER_COUNT, "DCNAME" => DCNAME, "DOMAIN" => DOMAIN}

      end
    end

    1.upto(CLIENT_COUNT) do |n|
      config.vm.define "consul-client0#{n}" do |client|
        client.vm.hostname = "consul-client0#{n}"
        client.vm.network "private_network", ip: "192.168.56.#{60+n}"
        client.vm.provision "shell",inline: "cd /vagrant ; bash scripts/consul.sh", env: {"CONSUL_VERSION" => CONSUL_VERSION, "SERVER_COUNT" => SERVER_COUNT, "DCNAME" => DCNAME, "DOMAIN" => DOMAIN}

      end
    end
  end
