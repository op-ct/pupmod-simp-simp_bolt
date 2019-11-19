# bolt plan run --boltdir=$PWD simp_bolt::painstall -t target1,target2,target3,target4 agent_version="5.5.17-1.el7" update=false

BASIC_TARGETS = [
  - 'centos/7',
  - 'centos/6',
  - 'generic/centos8',
  - 'ubuntu/trusty64',
]
SUBNET       = '10.10.111'
IP           = 100
n            = 0
TARGET_HOSTS = Hash[ BASIC_TARGETS.map{|os| n += 1; ["target#{n}" ,{ :os => os, :ip => "#{SUBNET}.#{IP + n}" } ]}]
HOSTS        = { 'bolt' => { :ip => "#{SUBNET}.#{IP}", :os => 'centos/7' } }.merge(TARGET_HOSTS)


Vagrant.configure('2') do |c|
  c.ssh.insert_key = false

  c.vm.box = "centos/7"

  TARGET_HOSTS.each do |host, data|
    c.vm.define host do |v|
      v.vm.box = data[:os]
      v.vm.network 'private_network', ip: data[:ip]
      v.vm.synced_folder '.', '/vagrant', disabled: true
    end
  end

  c.vm.define 'bolt', primary: true do |v|
    v.vm.box = HOSTS['bolt'][:os]
    v.vm.network 'private_network', ip: HOSTS['bolt'][:ip]

    v.vm.provision 'install bolt', type: 'shell', inline: <<-INLINE.gsub(/^ {6}/,'')
      rpm -Uvh https://yum.puppet.com/puppet-tools-release-el-7.noarch.rpm
      yum install -y puppet-bolt
      yum install -y pdk
    INLINE

    v.vm.provision 'configure bolt', type: 'shell', privileged: false, inline: <<-INLINE.gsub(/^ {6}/,'')
      mkdir -p  ~/.puppetlabs/bolt
      echo 'disabled: true' >> ~/.puppetlabs/bolt/analytics.yaml
      test -f $HOME/.ssh/id_rsa || ssh-keygen -N '' -f $HOME/.ssh/id_rsa
      rm -f $HOME/.ssh/id_rsa.pub
    INLINE

    # Is there a better or more portable way of doing this?
    ssh_key_file = File.join( ENV['VAGRANT_HOME'] || File.join(ENV['HOME'], '.vagrant.d'), 'insecure_private_key')
    v.vm.provision "file", source: ssh_key_file, destination: '~/.ssh/id_rsa'
    v.vm.provision 'set up ssh', type: 'shell', inline: HOSTS.map{ |k,v| "echo '#{v[:ip]}  #{k}' >> /etc/hosts" }.join("\n")

    v.vm.provision 'configure ~/proj_dir', type: 'shell', privileged: false, inline: <<-INLINE.gsub(/^ {6}/,'')
      mkdir -p  ~/proj_dir/modules
      cd ~/proj_dir/modules/
      ln -s /vagrant simp_bolt
      test -f ~/proj_dir/bolt.yaml || { printf -- "---\n%s" 'format: json'  > ~/proj_dir/bolt.yaml; }
    INLINE

    v.vm.provision 'install quality-of-life tools', type: 'shell', inline: 'yum install -y vim-enhanced htop bind-utils'

    v.trigger.after :up do |trigger|
      trigger.only_on = 'bolt'
      trigger.info = 'All VMs are built; setting up SSH'
      trigger.run_remote = {
        privileged: false,
        inline: TARGET_HOSTS.map{ |k,v| "ssh -tt -oStrictHostKeyChecking=no #{k} ls" }.join("\n")
      }
    end
  end


end
# vim: set syntax=ruby ts=2 sw=2 et:
