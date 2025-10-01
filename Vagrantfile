# to make sure the nodes are created in the defined order, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

DC_DOMAIN               = "example.test"
DC_IP_ADDRESS           = "10.20.20.10"
SQL_FC_NAME             = "SQLC"
SQL_FC_IP_ADDRESS       = "10.20.20.100"
SQL1_IP_ADDRESS         = "10.20.20.11"
SQL2_IP_ADDRESS         = "10.20.20.12"
SQL_IP_ADDRESSES        = [SQL1_IP_ADDRESS, SQL2_IP_ADDRESS]
SQL_CLUSTER_NAME        = "SQL" # NB this must not be the same as SQL_FC_NAME, DC_DOMAIN, or the SQL Server Instance name.
SQL_CLUSTER_IP_ADDRESS  = "10.20.20.101"

Vagrant.configure("2") do |config|
  config.vm.box = "windows-2022-uefi-amd64"

  config.vm.provider "libvirt" do |lv, config|
    lv.memory = 4*1024
    lv.cpus = 4
    lv.cpu_mode = "host-passthrough"
    #lv.nested = true
    lv.keymap = "pt"
    config.vm.synced_folder ".", "/vagrant", type: "smb", smb_username: ENV["USER"], smb_password: ENV["VAGRANT_SMB_PASSWORD"]
  end

  config.vm.define "dc" do |config|
    # use the plaintext WinRM transport and force it to use basic authentication.
    # NB this is needed because the default negotiate transport stops working
    #    after the domain controller is installed.
    #    see https://groups.google.com/forum/#!topic/vagrant-up/sZantuCM0q4
    config.winrm.transport = :plaintext
    config.winrm.basic_auth_only = true
    config.vm.hostname = "dc"
    config.vm.network :private_network, ip: DC_IP_ADDRESS
    config.vm.provision "shell", path: "ps.ps1", args: ["provision-domain-controller-create.ps1", DC_DOMAIN]
    config.vm.provision "shell", reboot: true
    config.vm.provision "shell", path: "ps.ps1", args: "provision-domain-controller-wait-for-ready.ps1"
    config.vm.provision "shell", path: "ps.ps1", args: "provision-domain-controller-set-vagrant-domain-admin.ps1"
    config.vm.provision "shell", path: "ps.ps1", args: ["provision-domain-controller-configure.ps1", SQL_FC_NAME]
    config.vm.provision "shell", path: "ps.ps1", args: "provision-chocolatey.ps1"
    config.vm.provision "shell", path: "ps.ps1", args: "provision-base.ps1"
    config.vm.provision "shell", path: "ps.ps1", args: "provision-certificate.ps1"
    config.vm.provision "shell", path: "ps.ps1", args: ["provision-failover-cluster-storage-share.ps1", SQL_FC_NAME]
    config.vm.provision "shell", path: "ps.ps1", args: "provision-sql-server-management-studio.ps1"
  end

  SQL_IP_ADDRESSES.each_with_index do |ip_address, i|
    config.vm.define "sql#{i+1}" do |config|
      config.vm.hostname = "sql#{i+1}"
      config.vm.network :private_network, ip: ip_address
      config.vm.provision "shell", path: "ps.ps1", args: "provision-prepare-for-sysprep.ps1"
      config.vm.provision "windows-sysprep"
      config.vm.provision "shell", path: "ps.ps1", args: ["provision-domain-join.ps1", DC_DOMAIN, DC_IP_ADDRESS]
      config.vm.provision "reload"
      config.vm.provision "shell", path: "ps.ps1", args: "provision-chocolatey.ps1"
      config.vm.provision "shell", path: "ps.ps1", args: "provision-base.ps1"
      config.vm.provision "shell", path: "ps.ps1", args: ["provision-certificate.ps1", "#{SQL_CLUSTER_NAME}.#{DC_DOMAIN}", SQL_CLUSTER_IP_ADDRESS, ip_address]
      config.vm.provision "shell", path: "ps.ps1", args: ["provision-failover-cluster.ps1", i == 0 ? "create" : "join", SQL_FC_NAME, SQL_FC_IP_ADDRESS]
      config.vm.provision "shell", path: "ps.ps1", args: ["provision-sql-server.ps1", DC_DOMAIN, SQL_FC_NAME, i == 0 ? "create" : "join", SQL_CLUSTER_NAME, SQL_CLUSTER_IP_ADDRESS]
      config.vm.provision "shell", path: "ps.ps1", args: ["list-service-principals.ps1", DC_DOMAIN]
      config.vm.provision "shell", path: "ps.ps1", args: ["examples/powershell/create-database-TheSimpsons.ps1"] if i == 0
    end
  end
end
