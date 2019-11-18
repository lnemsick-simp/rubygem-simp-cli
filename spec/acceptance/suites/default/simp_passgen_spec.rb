require 'spec_helper_acceptance'

test_name 'simp passgen'

describe 'simp passgen' do

  hosts.each do |host|
    context 'Puppet master set up' do
      include_examples 'fixtures move', host
      include_examples 'simp asset manual install', host
      include_examples 'test environments set up', host
      include_examples 'puppetserver set up', host
    end

    context 'initial passgen secret generation' do
      [
        'old_simplib',
        'new_simplib_legacy_passgen',
        'new_simplib_libkv_passgen'
      ].each do |env|
        it "should configure the puppet environment #{env}" do
          # configure the environment for both the puppetserver and agent
          on(host, "puppet config set --section master environment #{env}")
          on(host, "puppet config set --section agent environment #{env}")

          # restart the puppetserver
          cmds = [
            'puppet resource service puppetserver ensure=stopped',
            'puppet resource service puppetserver ensure=running'
          ]
          on(host, "#{cmds.join('; ')}")

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

        it 'should apply manifest' do
          retry_on(host, 'puppet agent -t', :desired_exit_codes => [0],
            :max_retries => 5, :verbose => true.to_s)
        end

        [
         "/var/passgen_test/#{env}-passgen_test_default",
         "/var/passgen_test/#{env}-passgen_test_c0_8",
         "/var/passgen_test/#{env}-passgen_test_c1_1024",
         "/var/passgen_test/#{env}-passgen_test_c2_20",
         "/var/passgen_test/#{env}-passgen_test_c2_only"
        ].each do |file|
          it "should create #{file}" do
            expect( file_exists_on(host, file) ).to be true
          end
        end
      end
    end
  end
end
