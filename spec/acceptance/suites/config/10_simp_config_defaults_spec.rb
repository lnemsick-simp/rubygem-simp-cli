require 'spec_helper_acceptance'

test_name 'simp config using defaults'

# Tests `simp config`, alone, in a server configuration that is akin to
# installation from RPM.
#
# - The minimal server set up only has modules and assets required for
#   the limited `simp config` testing done here.
# - Does NOT support network configuration via `simp config`.
# - Does NOT support `simp bootstrap` testing. Bootstrap tests must install
#   most of the components in one of simp-core's Puppetfiles in order to
#   have everything needed for bootstrap testing. See simp-core acceptance
#   tests for bootstrap tests.
#
describe 'simp config using defaults' do

  hosts.each do |host|
    it 'should create and configure production env primarily using defaults' do
      cmd = [
       'simp config',
        # Force defaults if not otherwised specified and do not allow queries.
        # This means `simp config` will fail if it encounters any unspecified
        # item that was not preassigned and could not be set by a default.
       '-f -D',

        # Subsequent <key=value> command line parameters preassign item values
        # (just like an answers file). Some are for items that don't have
        # defaults and some are for items for which we don't want to use their
        # defaults.
        #
        # Do not mess with the network!
       'cli::network::set_up_nic=false',
       'cli::network::interface=eth1',  # ASSUMES eth1 is the private network

        # Don't depend upon the system default being the same on different
        # host boxes
       'simp_options::ntp::servers=0.north-america.pool.ntp.org',

        # Set password hashes
        # - All hashes correspond to 'P@ssw0rdP@ssw0rd'
        # - Be sure to put <key=value> in single quotes to prevent any bash
        #   interpretation.
       "'grub::password=grub.pbkdf2.sha512.10000.DE78658C8482E4F3752B61942622345CB22BF23FECDDDCA41D9891FF7569376D3177D11945AF344267B04B44227475BDD520367D5A492EEADCBAB6AA76718AFA.2B08D03310E1514F517A59D9F1B174C73DC15B9C02010F88DC6E6FC8C869D16B9B38E9004CB6382AFE3A68BFC29E14B49C48360ED829D6EDC25E05F5609069F8'",
       "'simp_openldap::server::conf::rootpw={SSHA}oIQoj6htrx7TnXwhTOY57ThnklOJkD8m'",
       "'cli::local_priv_user_password=$6$l69r7t36$WZxDVhvdMZeuL0vRvOrSLMKWxxQbuK1j8t0vaEq3BW913hjOJhRNTxqlKzDflPW7ULPwkBa6xdfcca2BlGoq/.'"
       ].join(' ')
       result = on(host, cmd)
    end

    it 'should create a production Puppet environment'
    it 'should create a simp_config_settings.yaml global hiera file'
    it 'should create a SIMP server hiera file'
    it 'should set SIMP scenario in site.pp'
    it 'should create a production secondary environment'
    it 'should generate FakeCA host certs'
    it 'should configure Puppet'
    it 'should create privileged user'
    it 'should ensure puppet server entry is in /etc/hosts'
  end
end

# set ENV variable for 'simp config'
#
# other paths in decision tree
# - do not set grub password
# - has simp_filesystem.repo
#    it 'should disable CentOS yum repos'
# - does not have simp_filesystem.repo, but do not use internet repos
# - is not ldap server
# - specify log servers, but do not specify failover log servers
# - specify log servers and specify failover log servers
# - has simp user from ISo
# - does not have simp user from ISO, want priv local user, user exist, user does not have keys
# - does not have simp user from ISO, want priv local user, user exists, user has keys
# - does not have simp user from ISO, do not want priv local user
