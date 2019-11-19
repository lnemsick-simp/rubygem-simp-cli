shared_examples 'configure puppet env' do |host,env|

  it "should set the puppet environment to #{env} on #{host}" do
    # configure the environment for both the puppetserver and agent
    on(host, "puppet config set --section master environment #{env}")
    on(host, "puppet config set --section agent environment #{env}")
  end

  it "should restart the puppetserver on #{host}" do
    cmds = [
      'puppet resource service puppetserver ensure=stopped',
      'puppet resource service puppetserver ensure=running'
    ]
    on(host, "#{cmds.join('; ')}")
  end

  it "should wait for the restarted puppetserver to be available on #{host}" do
    # wait for it to come up
    master_fqdn = fact_on(host, 'fqdn')
    puppetserver_status_cmd = [
      'curl -sk',
      "--cert /etc/puppetlabs/puppet/ssl/certs/#{master_fqdn}.pem",
      "--key /etc/puppetlabs/puppet/ssl/private_keys/#{master_fqdn}.pem",
      "https://#{master_fqdn}:8140/status/v1/services",
      '| python -m json.tool',
      '| grep state',
      '| grep running'
    ].join(' ')
    retry_on(host, puppetserver_status_cmd, :retry_interval => 10)
  end
end
