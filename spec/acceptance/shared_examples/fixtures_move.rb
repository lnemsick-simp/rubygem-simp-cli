# move fixtures copies into a staging dir
#
shared_examples 'fixtures move' do |master|

  context 'staging of fixtures' do
    let(:fixtures_orig_dest) { '/etc/puppetlabs/code/environments/production/modules' }
    let(:fixtures_staging_dir) { '/root/fixtures' }

    it 'should move assets from fixtures install dir to staging dir' do
      on(master, "mkdir -p #{fixtures_staging_dir}/assets")
      on(master, "mv #{fixtures_orig_dest}/environment_skeleton #{fixtures_staging_dir}/assets")
      on(master, "mv #{fixtures_orig_dest}/rsync_data #{fixtures_staging_dir}/assets")
      on(master, "mv #{fixtures_orig_dest}/rubygem_simp_cli #{fixtures_staging_dir}/assets")
      on(master, "mv #{fixtures_orig_dest}/simp_selinux_policy #{fixtures_staging_dir}/assets")
    end

    it 'should move modules from fixtures install dir to staging dir' do
      on(master, "mkdir -p #{fixtures_staging_dir}/modules")
      on(master, "mv #{fixtures_orig_dest}/* #{fixtures_staging_dir}/modules")
    end

    it 'should fix problems with rsync skeleton' do
      # First 2 fixes are because empty directories don't survive fixtures copy process.
      # TODO: Replace simp-rsync-skeleton install with git clone instead?
      on(master, "mkdir #{fixtures_staging_dir}/assets/rsync_data/rsync/RedHat/6/bind_dns/default/named/var/tmp")
      on(master, "mkdir #{fixtures_staging_dir}/assets/rsync_data/rsync/RedHat/6/bind_dns/default/named/var/log")

      # This fix is for a bug in .rsync.facl...lists file that was removed from the skeleton.
      # TODO: Remove this when the bug is fixed.
      cmd = [
        'cp',
        "#{fixtures_staging_dir}/assets/rsync_data/rsync/RedHat/6/bind_dns/default/named/etc/rndc.key",
        "#{fixtures_staging_dir}/assets/rsync_data/rsync/RedHat/7/bind_dns/default/named/etc/rndc.key"
      ].join(' ')
      on(master, cmd)
    end
  end
end
