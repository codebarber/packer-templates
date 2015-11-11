# Cookbook Name:: travis_packer_templates
# Recipe:: default
#
# Copyright 2015, Travis CI GmbH
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

ruby_block 'import packer env vars' do
  block do
    ::Dir.glob("#{node['travis_packer_templates']['packer_env_dir']}/*") do |f|
      attr_name = ::File.basename(f)
      attr_value = ::File.read(f).strip
      next if attr_value.empty?
      Chef::Log.info("Setting travis_packer_templates.env.#{attr_name} = #{attr_value}")
      node.set['travis_packer_templates']['env'][attr_name] = attr_value
    end
  end
end

ruby_block 'set group based on packer env vars' do
  block do
    env = node['travis_packer_templates']['env']
    if env['TRAVIS_COOKBOOKS_BRANCH'] == 'master' &&
       env['TRAVIS_COOKBOOKS_SHA'] == '' &&
       env['PACKER_TEMPLATES_BRANCH'] == 'master' &&
       env['PACKER_TEMPLATES_SHA'] !~ /dirty/
      Chef::Log.info('Setting travis_packer_templates.job_board.group = edge')
      node.set['travis_packer_templates']['job_board']['group'] = 'edge'
    end
  end
end

ruby_block 'set system_info.cookbooks_sha' do
  block do
    sha = node['travis_packer_templates']['env']['TRAVIS_COOKBOOKS_SHA'].to_s
    Chef::Log.info("Setting system_info.cookbooks_sha = #{sha.inspect}")
    node.set['system_info']['cookbooks_sha'] = sha
  end
end

template '/etc/default/job-board-register' do
  source 'etc-default-job-board-register.sh.erb'
  owner 'root'
  group 'root'
  mode 0644
  variables(
    dist: node['travis_packer_templates']['job_board']['dist'],
    group: node['travis_packer_templates']['job_board']['group'],
    branch: node['travis_packer_templates']['env']['PACKER_TEMPLATES_BRANCH'],
    languages: node['travis_packer_templates']['job_board']['languages']
  )
end

ruby_block 'set travis_packer_templates.packages from ' \
           'travis_packer_templates.packages_file' do
  block do
    packages_file = node['travis_packer_templates']['packages_file']
    if ::File.exist?(packages_file)
      packages_lines = ::File.readlines(packages_file)
      packages = packages_lines.map(&:strip).reject { |l| l =~ /^#/ }.uniq
      node.set['travis_packer_templates']['packages'] = packages
      Chef::Log.info("Loaded #{packages.length} packages from #{packages_file}")
    else
      Chef::Log.info("No file found at #{packages_file}")
    end
  end
end

ruby_block 'install packages from travis_packer_templates.packages' do
  block do
    Array(node['travis_packer_templates']['packages']).each_slice(10) do |slice|
      resource = Chef::Resource::Package.new(slice, run_context)
      resource.retries 2
      resource.run_action(:install)
      resource.run_action(:upgrade)
    end
  end
end
