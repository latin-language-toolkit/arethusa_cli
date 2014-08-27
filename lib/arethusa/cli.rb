require 'thor'
require 'json'

module Arethusa
  class CLI < Thor
    require 'arethusa/cli/version'
    require 'arethusa/cli/subcommand'

    require 'arethusa/cli/generator'
    require 'arethusa/cli/transformer'

    include Thor::Actions

    register(Generator, Generator.namespace, "#{Generator.namespace} [ACTION]", 'Generates Arethusa files. Call "arethusa generate" to learn more')
    register(Transformer, Transformer.namespace, "#{Transformer.namespace} [ACTION]", 'Tranforms Alpheios conf files. Call "arethusa transform" to learn more')

    desc 'build', 'Creates a tar archive to be used for deployment'
    method_option :minify, aliases: '-m', type: :boolean, default: true,
      desc: 'Minifies Arethusa before building'
    def build
      minify if options[:minify]
      empty_directory('deployment')
      @filename = "#{tar_name}#{ending}"
      create_tgz
      say_status(:built, archive_path)
    end

    desc 'deploy ADDRESS DIRECTORY', 'Deploys an Arethusa archive through ssh'
    long_desc <<-EOF
Uses ssh to deploy Arethus on a remote server.

By default a new Arethusa archive file will get created in the process
(overridden by -f), which will be transferred through ssh to its remote
location, where the files are decompressed.

A regular ssh connection is used. If you need to specify additional options
to the ssh command  (like using a specific identity file), use -o and
pass them as a string. Here's a rather complex usage example:

arethusa deploy user@hostname /var/www -f arethusa-1.0.0.tgz -o "-i key.pem"
EOF
    method_option :options, aliases: '-o',
      desc: 'Options to pass to the ssh command'
    method_option :file, aliases: '-f',
      desc: 'Archive file to use - builds a new one by default'
    method_option :small, aliases: '-s', type: :boolean, default: false,
      desc: 'Deploys only Arethusa files without third party code'
    method_option :minify, aliases: '-m', type: :boolean, default: true,
      desc: 'Minifies Arethusa before building'
    def deploy(address, directory)
      @address = address
      @directory = directory
      @ssh_options = options[:options]
      @archive = options[:file]

      @small = options[:small]

      minify if options[:minify] &! @archive
      execute
      say_status(:deployed, "at #{@address} - #{@directory}")
    end

    desc 'merge FILE', 'Merge Arethusa configuration files'
    method_option :base_path, aliases: '-b',
      desc: 'Base path to conf files to be included'
    method_option :minify, aliases: '-m',
      desc: 'Print the resulting JSON minified'
    def merge(file)
      @conf = read_conf(file)
      @conf_dir = options[:base_path] || app_dir
      traverse_and_include(@conf)

      if options[:minify]
        puts @conf.to_json
      else
        puts JSON.pretty_generate(@conf, indent: '  ')
      end
    end

    no_commands do
      def minify
        if `grunt minify:css minify`
          say_status(:success, 'minified Arethusa')
        else
          say_status(:error, 'minification failed')
          exit
        end
      end

      # For deploy command
      def execute
        `#{archive_to_use} | #{ssh} #{decompress}`
      end

      def compress
        "tar -zc #{folders_to_deploy.join(' ')}"
      end

      def archive_to_use
        @archive ? "cat #{@archive}" : compress
      end

      def ssh
        "ssh #{@ssh_options} #{@address}"
      end

      def decompress
        "tar -zxC #{@directory}"
      end

      # For build command
      def create_tgz
        `tar -zcf #{archive_path} #{folders_to_deploy.join(' ')}`
      end

      def folders_to_deploy
        if @small
          %w{ app dist favicon.ico }
        else
          %w{ app bower_components dist vendor favicon.ico }
        end
      end

      def archive_path
        "deployment/#{@filename}"
      end

      def tar_name
        [tar_namespace, timestamp, git_branch, commit_sha].join('-')
      end

      def ending
        '.tgz'
      end

      def tar_namespace
        'arethusa'
      end

      def git_branch
        `git rev-parse --abbrev-ref HEAD`.strip
      end

      def timestamp
        Time.now.to_i
      end

      def commit_sha
        `git rev-parse --short HEAD`.strip
      end

      # methods for merging
      def app_dir
        "app"
      end

      def traverse_and_include(conf)
        inside @conf_dir do
          traverse(conf)
        end
      end

      def traverse(conf)
        clone = conf.clone
        clone.each do |key, value|
          if value.is_a?(Hash)
            traverse(conf[key])
          elsif key == 'fileUrl'
            additional_conf = read_conf(value)
            conf.delete(key)
            conf.merge!(additional_conf)
            traverse(additional_conf)
          end
        end
      end

      def read_conf(path)
        JSON.parse(File.read(path))
      end
    end
  end
end
