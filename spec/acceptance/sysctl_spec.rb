require 'spec_helper_acceptance'

test_name 'Augeasproviders Sysctl'

describe 'Sysctl Tests' do
  hosts.each do |host|
    context "on #{host}" do
      let(:sysctl_conf) do
        os_name = fact_on(host, 'os.name')
        os_major = fact_on(host, 'os.release.major') || '0'
        if (os_name == 'Debian' && os_major.to_i >= 13) ||
           (os_name == 'Ubuntu' && os_major.delete('.').to_i >= 2604)
          '/etc/sysctl.d/99-puppet.conf'
        else
          '/etc/sysctl.conf'
        end
      end
      context 'file based updates' do
        let(:manifest) do
          <<-EOM
            sysctl { 'fs.nr_open':
              value => '100000',
              apply => false
            }
          EOM
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'has applied successfuly in the sysctl config but not live' do
          result = on(host, 'sysctl -n fs.nr_open').stdout.strip
          expect(result).not_to eql('100000')

          on(host, "sysctl -p #{sysctl_conf}", accept_all_exit_codes: true)
          result = on(host, 'sysctl -n fs.nr_open').stdout.strip
          expect(result).to eql('100000')
        end
      end

      context 'full updates' do
        let(:manifest) do
          <<-EOM
            sysctl { 'fs.nr_open':
              value => '100001'
            }
          EOM
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'applies successfuly in the config and live' do
          result = on(host, 'sysctl -n fs.nr_open').stdout.strip
          expect(result).to eql('100001')
        end

        context 'when given an invalid key' do
          let(:manifest) do
            <<-EOM
              sysctl { 'fs.this_cannot_exist':
                value => 'I like bread'
              }
            EOM
          end

          it 'fails to apply to the system' do
            apply_manifest_on(host, manifest, expect_failures: true)
          end
        end

        context 'when silent' do
          let(:manifest) do
            <<-EOM
              sysctl { 'fs.nr_open':
                value  => '100002',
                silent => true
              }
            EOM
          end

          # Using puppet_apply as a helper
          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end
        end

        context 'when silent and given a key that does not exist' do
          let(:manifest) do
            <<-EOM
              sysctl { 'fs.this_cannot_exist':
                value  => 'I like bread',
                silent => true
              }
            EOM
          end

          # Using puppet_apply as a helper
          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end
        end

        context 'when only applying to the running system' do
          let(:manifest) do
            <<-EOM
              sysctl { 'kernel.pty.max':
                value   => 4097,
                apply   => true,
                persist => false
              }
            EOM
          end

          # Using puppet_apply as a helper
          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'is not in default config file' do
            expect(file_contents_on(host, sysctl_conf)).not_to match(%r{kernel\.pty\.max})
          end
        end

        context 'when only applying to the filesystem' do
          let(:manifest) do
            <<-EOM
              sysctl { 'kernel.pty.max':
                comment => 'just a test',
                value   => 4098,
                apply   => false,
                persist => true
              }
            EOM
          end

          # Using puppet_apply as a helper
          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'is in default config file' do
            expect(file_contents_on(host, sysctl_conf)).to match(%r{kernel\.pty\.max = 4098})
          end

          it 'is not changed on the running system' do
            result = on(host, 'sysctl -n kernel.pty.max').stdout.strip
            expect(result).to eql('4097')
          end
        end

        context 'when deleting an entry' do
          let(:manifest) do
            <<-EOM
              sysctl { 'kernel.pty.max':
                ensure  => absent
              }
            EOM
          end

          # Using puppet_apply as a helper
          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'is not in default config file' do
            expect(file_contents_on(host, sysctl_conf)).not_to match(%r{kernel\.pty\.max})
          end

          it 'is not changed on the running system' do
            result = on(host, 'sysctl -n kernel.pty.max').stdout.strip
            expect(result).to eql('4097')
          end
        end

        context 'when using a target file' do
          let(:manifest) do
            <<-EOM
              if $facts['os']['family'] == 'RedHat' and versioncmp($facts['os']['release']['major'], '9') >= 0 {
                package { 'systemd-udev':
                  ensure => 'installed',
                }
                Package['systemd-udev'] -> Sysctl <| |>
              }
              sysctl { 'fs.nr_open':
                value  => '100001',
                target => '/etc/sysctl.d/20-fs.conf'
              }

              sysctl { 'fs.inotify.max_user_watches':
                value  => '8193',
                target => '/etc/sysctl.d/20-fs.conf'
              }
            EOM
          end

          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'has correct file contents' do
            expect(file_contents_on(host, sysctl_conf)).to match(%r{fs\.nr_open = 100002})
            expect(file_contents_on(host, sysctl_conf)).not_to match(%r{fs\.inotify\.max_user_watches})
            expect(file_contents_on(host, '/etc/sysctl.d/20-fs.conf')).to match(%r{fs\.nr_open = 100001})
            expect(file_contents_on(host, '/etc/sysctl.d/20-fs.conf')).to match(%r{fs\.inotify\.max_user_watches = 8193})
          end

          context 'when deleting an entry' do
            let(:manifest) do
              <<-EOM
                sysctl { 'fs.inotify.max_user_watches':
                  ensure => absent,
                  target => '/etc/sysctl.d/20-fs.conf'
                }
              EOM
            end

            it 'works with no errors' do
              apply_manifest_on(host, manifest, catch_failures: true)
            end

            it 'is idempotent' do
              apply_manifest_on(host, manifest, { catch_changes: true })
            end

            it 'has been removed from the system' do
              expect(file_contents_on(host, '/etc/sysctl.d/20-fs.conf')).not_to match(%r{fs\.inotify\.max_user_watches})
            end
          end
        end
      end

      context 'when managing comments' do
        let(:manifest) do
          <<-EOM
            sysctl { 'net.ipv4.ip_default_ttl':
              value   => '63',
              comment => 'Für tests',
            }
          EOM
        end

        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'has the comment above the entry' do
          expect(file_contents_on(host, sysctl_conf)).to match(%r{^# net\.ipv4\.ip_default_ttl: Für tests\nnet\.ipv4\.ip_default_ttl = 63$})
        end

        it 'applies the value live' do
          expect(on(host, 'sysctl -n net.ipv4.ip_default_ttl').stdout.strip).to eql('63')
        end

        context 'when changing the comment' do
          let(:manifest) do
            <<-EOM
              sysctl { 'net.ipv4.ip_default_ttl':
                value   => '63',
                comment => 'changed',
              }
            EOM
          end

          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'replaces the comment' do
            content = file_contents_on(host, sysctl_conf)
            expect(content).to match(%r{^# net\.ipv4\.ip_default_ttl: changed\nnet\.ipv4\.ip_default_ttl = 63$})
            expect(content.scan(%r{^# net\.ipv4\.ip_default_ttl:}).length).to eq(1)
          end
        end

        context 'when removing the comment' do
          let(:manifest) do
            <<-EOM
              sysctl { 'net.ipv4.ip_default_ttl':
                value   => '63',
                comment => '',
              }
            EOM
          end

          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'removes the comment but keeps the entry' do
            content = file_contents_on(host, sysctl_conf)
            expect(content).not_to match(%r{^# net\.ipv4\.ip_default_ttl:})
            expect(content).to match(%r{^net\.ipv4\.ip_default_ttl = 63$})
          end
        end

        context 'when running in noop mode' do
          let(:manifest) do
            <<-EOM
              sysctl { 'net.ipv4.ip_default_ttl':
                value => '62',
              }
            EOM
          end

          it 'reports the change' do
            result = apply_manifest_on(host, manifest, noop: true, catch_failures: true)
            expect(result.stdout).to match(%r{Sysctl\[net\.ipv4\.ip_default_ttl\]/value: .*'62' \(noop\)})
          end

          it 'does not change the config file' do
            expect(file_contents_on(host, sysctl_conf)).to match(%r{^net\.ipv4\.ip_default_ttl = 63$})
          end

          it 'does not change the running system' do
            expect(on(host, 'sysctl -n net.ipv4.ip_default_ttl').stdout.strip).to eql('63')
          end
        end

        context 'when the kernel rejects the value' do
          let(:manifest) do
            <<-EOM
              sysctl { 'net.ipv4.ip_default_ttl':
                value => '1000',
              }
            EOM
          end

          it 'fails to apply to the system' do
            apply_manifest_on(host, manifest, expect_failures: true)
          end

          it 'does not change the config file' do
            expect(file_contents_on(host, sysctl_conf)).to match(%r{^net\.ipv4\.ip_default_ttl = 63$})
          end

          it 'does not change the running system' do
            expect(on(host, 'sysctl -n net.ipv4.ip_default_ttl').stdout.strip).to eql('63')
          end
        end
      end

      context 'when using the val parameter' do
        let(:manifest) do
          <<-EOM
            sysctl { 'net.ipv4.tcp_fin_timeout':
              val => '59',
            }
          EOM
        end

        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'applies successfully in the config and live' do
          expect(file_contents_on(host, sysctl_conf)).to match(%r{^net\.ipv4\.tcp_fin_timeout = 59$})
          expect(on(host, 'sysctl -n net.ipv4.tcp_fin_timeout').stdout.strip).to eql('59')
        end
      end

      context 'when the value has multiple fields' do
        let(:manifest) do
          <<-EOM
            sysctl { 'net.ipv4.ip_local_port_range':
              value => '32769    60998',
            }
          EOM
        end

        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent despite whitespace differences' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'applies successfully in the config and live' do
          expect(file_contents_on(host, sysctl_conf)).to match(%r{^net\.ipv4\.ip_local_port_range = 32769\s+60998$})
          expect(on(host, 'sysctl -n net.ipv4.ip_local_port_range').stdout.split).to eql(%w[32769 60998])
        end
      end

      context 'when the config file has duplicate entries' do
        let(:manifest) do
          <<-EOM
            sysctl { 'net.ipv4.tcp_keepalive_time':
              value   => '7002',
              comment => 'deduplicated',
            }
          EOM
        end

        it 'has duplicate entries' do
          on(host, "printf 'net.ipv4.tcp_keepalive_time = 7000\\nnet.ipv4.tcp_keepalive_time = 7001\\n' >> #{sysctl_conf}")
          expect(file_contents_on(host, sysctl_conf).scan(%r{^net\.ipv4\.tcp_keepalive_time =}).length).to eq(2)
        end

        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'keeps a single entry with the new value' do
          content = file_contents_on(host, sysctl_conf)
          expect(content.scan(%r{^net\.ipv4\.tcp_keepalive_time =}).length).to eq(1)
          expect(content.scan(%r{^# net\.ipv4\.tcp_keepalive_time:}).length).to eq(1)
          expect(content).to match(%r{^# net\.ipv4\.tcp_keepalive_time: deduplicated\nnet\.ipv4\.tcp_keepalive_time = 7002$})
          expect(on(host, 'sysctl -n net.ipv4.tcp_keepalive_time').stdout.strip).to eql('7002')
        end

        context 'when deleting the entry' do
          let(:manifest) do
            <<-EOM
              sysctl { 'net.ipv4.tcp_keepalive_time':
                ensure => absent,
              }
            EOM
          end

          it 'has duplicate entries' do
            on(host, "printf 'net.ipv4.tcp_keepalive_time = 7003\\n' >> #{sysctl_conf}")
            expect(file_contents_on(host, sysctl_conf).scan(%r{^net\.ipv4\.tcp_keepalive_time =}).length).to eq(2)
          end

          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'removes all entries and the comment' do
            expect(file_contents_on(host, sysctl_conf)).not_to match(%r{net\.ipv4\.tcp_keepalive_time})
          end
        end
      end

      context 'when silent with a comment and given a key that does not exist' do
        let(:manifest) do
          <<-EOM
            sysctl { 'fs.this_cannot_exist':
              value   => 'I like bread',
              comment => 'never written',
              silent  => true,
            }
          EOM
        end

        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'is not in default config file' do
          expect(file_contents_on(host, sysctl_conf)).not_to match(%r{fs\.this_cannot_exist})
        end
      end

      context 'when a key appears after prefetch' do
        let(:manifest) do
          <<-EOM
            $iproute = $facts['os']['family'] ? {
              'RedHat' => 'iproute',
              default  => 'iproute2',
            }

            package { $iproute:
              ensure => installed,
            }

            # Prefetch happens when the first sysctl resource is evaluated
            sysctl { 'net.ipv4.ip_default_ttl':
              value => '63',
            }
            -> exec { 'create sysctltest0':
              command => 'ip link add sysctltest0 type veth peer name sysctltest1',
              unless  => 'ip link show sysctltest0',
              path    => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'],
              require => Package[$iproute],
            }
            -> sysctl { 'net.ipv4.conf.sysctltest0.forwarding':
              value   => '1',
              persist => false,
            }
          EOM
        end

        after(:context) do
          on(host, 'ip link del sysctltest0', accept_all_exit_codes: true)
        end

        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'applies the value live' do
          expect(on(host, 'sysctl -n net.ipv4.conf.sysctltest0.forwarding').stdout.strip).to eql('1')
        end
      end

      context 'when managing many keys' do
        let(:settings) do
          on(host, "sysctl -a 2>/dev/null | grep '^net\\.ipv4\\.conf\\.lo\\.'").stdout.lines.map { |line| line.split('=', 2).map(&:strip) }
        end
        let(:manifest) do
          settings.map do |key, value|
            <<-EOM
              sysctl { '#{key}':
                value   => '#{value}',
                persist => false,
              }
            EOM
          end.join
        end

        it 'manages more keys than a single prefetch query' do
          expect(settings.length).to be > 30
        end

        it 'makes no changes when the values match' do
          apply_manifest_on(host, manifest, { catch_changes: true })
        end
      end
    end
  end
end
