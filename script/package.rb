#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'optparse'
require 'rbconfig'
require 'tmpdir'

module AICabinets
  module Packaging
    EXCLUDED_PATTERNS = [
      %r{\A\.git(?:/|$)},
      %r{\A\.github(?:/|$)},
      %r{\A\.svn(?:/|$)},
      %r{\A__MACOSX(?:/|$)},
      %r{\AThumbs\.db\z},
      %r{\A\.DS_Store\z},
      %r{~\z},
      %r{\.sw[op]\z}
    ].freeze

    DEFAULT_TIMESTAMP = Time.utc(2024, 1, 1).freeze

    class << self
      def run(argv = ARGV)
        options = parse_options(argv)

        root = File.expand_path('..', __dir__)
        registrar_path = File.join(root, 'aicabinets.rb')
        support_dir = File.join(root, 'aicabinets')
        version_file = File.join(support_dir, 'version.rb')

        validate_paths!(registrar_path, support_dir, version_file)
        version = extract_version(version_file)

        manifest = build_manifest(registrar_path, support_dir)

        print_manifest(manifest, options)

        output_dir = File.join(root, 'dist')
        output_path = File.join(output_dir, "aicabinets-#{version}.rbz")
        file_count = manifest[:files].size

        if options[:dry_run]
          puts "\nDry run complete. Would create: #{output_path} (#{file_count} files)."
          return 0
        end

        FileUtils.mkdir_p(output_dir)

        puts "Packaging AI Cabinets v#{version}..."
        if pack_with_rubyzip(manifest, output_path)
          puts "Created #{output_path} (#{file_count} files)."
          return 0
        end

        if pack_with_system_zip(manifest, output_path)
          puts "Created #{output_path} via system zip (#{file_count} files)."
          return 0
        end

        warn <<~ERROR
          Unable to package extension. Install the 'rubyzip' gem or ensure an OS archiver is available.
          Checked: RubyZip gem, #{windows? ? 'PowerShell Compress-Archive' : 'zip command'}.
        ERROR
        1
      rescue PackageError => e
        warn e.message
        1
      end

      private

      def parse_options(argv)
        options = { dry_run: false, verbose: false }
        parser = OptionParser.new do |opts|
          opts.banner = 'Usage: ruby script/package.rb [options]'
          opts.on('--dry-run', 'Show manifest without writing the RBZ') { options[:dry_run] = true }
          opts.on('--verbose', 'Print each archived entry') { options[:verbose] = true }
          opts.on('-h', '--help', 'Show this help message') do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)
        options
      end

      def validate_paths!(registrar_path, support_dir, version_file)
        raise PackageError, "Missing registrar: #{registrar_path}" unless File.file?(registrar_path)
        raise PackageError, "Missing support folder: #{support_dir}" unless Dir.exist?(support_dir)
        raise PackageError, "Missing version file: #{version_file}" unless File.file?(version_file)
      end

      def extract_version(path)
        data = File.read(path)
        match = data.match(/VERSION\s*=\s*['\"]([^'\"]+)['\"]/)
        raise PackageError, "Unable to parse VERSION from #{path}" unless match
        match[1]
      rescue Errno::ENOENT
        raise PackageError, "Missing version file: #{path}"
      end

      def build_manifest(registrar_path, support_dir)
        manifest = { directories: [], files: [] }

        manifest[:directories] << 'aicabinets/'
        manifest[:files] << { source: registrar_path, relative: 'aicabinets.rb' }

        Dir.chdir(support_dir) do
          Dir.glob('**/*', File::FNM_DOTMATCH).each do |relative|
            next if relative == '.' || relative == '..'
            normalized = relative.tr('\\', '/')
            next if excluded?(normalized)

            source = File.join(support_dir, normalized)
            if File.directory?(source)
              manifest[:directories] << File.join('aicabinets', normalized, '')
            else
              manifest[:files] << { source: source, relative: File.join('aicabinets', normalized) }
            end
          end
        end

        manifest[:directories] = manifest[:directories].uniq.sort
        manifest[:files] = manifest[:files].sort_by { |entry| entry[:relative] }
        manifest
      end

      def excluded?(relative)
        EXCLUDED_PATTERNS.any? { |pattern| pattern.match?(relative) }
      end

      def print_manifest(manifest, options)
        return unless options[:dry_run] || options[:verbose]

        puts 'Manifest:'
        puts '  Root entries:'
        puts '    - aicabinets.rb'
        puts '    - aicabinets/'

        puts '  Files:'
        manifest[:files].each do |entry|
          next if entry[:relative] == 'aicabinets.rb'
          puts "    - #{entry[:relative]}"
        end

        if options[:verbose]
          puts '  Directories:'
          manifest[:directories].each do |dir|
            next if dir == 'aicabinets/'
            puts "    - #{dir}"
          end
        end

        puts "  Total files: #{manifest[:files].size}"
      end

      def pack_with_rubyzip(manifest, output_path)
        require 'zip'
        FileUtils.rm_f(output_path)
        Zip.sort_entries = true if Zip.respond_to?(:sort_entries=)

        Zip::File.open(output_path, Zip::File::CREATE) do |zipfile|
          manifest[:directories].each do |dir|
            next if dir.empty?
            zipfile.mkdir(dir) unless zipfile.find_entry(dir)
            entry = zipfile.find_entry(dir)
            next unless entry
            entry.time = DEFAULT_TIMESTAMP
            entry.extra = ''.b
            entry.comment = nil
          end

          manifest[:files].each do |entry_info|
            zipfile.get_output_stream(entry_info[:relative]) do |stream|
              File.open(entry_info[:source], 'rb') do |file|
                IO.copy_stream(file, stream)
              end
            end
            entry = zipfile.find_entry(entry_info[:relative])
            next unless entry
            entry.time = DEFAULT_TIMESTAMP
            entry.extra = ''.b
            entry.comment = nil
          end
        end
        true
      rescue LoadError
        false
      rescue StandardError => e
        raise PackageError, "RubyZip packaging failed: #{e.message}"
      end

      def pack_with_system_zip(manifest, output_path)
        if windows?
          pack_with_powershell(manifest, output_path)
        else
          pack_with_zip_command(manifest, output_path)
        end
      end

      def pack_with_powershell(manifest, output_path)
        powershell = find_executable('powershell') || find_executable('pwsh')
        return false unless powershell

        staging_dir = Dir.mktmpdir('aicabinets-rbz-')
        begin
          stage_files(manifest, staging_dir)
          ps_output = powershell_escape(output_path)
          ps_staging = powershell_escape(staging_dir)
          command = <<~POWERSHELL
            Remove-Item -ErrorAction SilentlyContinue -Force #{ps_output};
            Set-Location #{ps_staging};
            Compress-Archive -Path 'aicabinets.rb','aicabinets' -DestinationPath #{ps_output} -Force;
          POWERSHELL
          system(powershell, '-NoProfile', '-Command', command)
        ensure
          FileUtils.remove_entry(staging_dir)
        end
      end

      def pack_with_zip_command(manifest, output_path)
        zip_cmd = find_executable('zip')
        return false unless zip_cmd

        staging_dir = Dir.mktmpdir('aicabinets-rbz-')
        begin
          stage_files(manifest, staging_dir)
          Dir.chdir(staging_dir) do
            FileUtils.rm_f(output_path)
            system(zip_cmd, '-X', '-q', '-r', output_path, 'aicabinets.rb', 'aicabinets')
          end
        ensure
          FileUtils.remove_entry(staging_dir)
        end
      end

      def stage_files(manifest, staging_dir)
        FileUtils.mkdir_p(staging_dir)
        manifest[:directories].each do |dir|
          next if dir.empty?
          FileUtils.mkdir_p(File.join(staging_dir, dir))
        end

        manifest[:files].each do |entry|
          destination = File.join(staging_dir, entry[:relative])
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(entry[:source], destination, preserve: true)
          File.utime(DEFAULT_TIMESTAMP, DEFAULT_TIMESTAMP, destination)
        end

        manifest[:directories].each do |dir|
          next if dir.empty?
          dir_path = File.join(staging_dir, dir)
          File.utime(DEFAULT_TIMESTAMP, DEFAULT_TIMESTAMP, dir_path) if File.exist?(dir_path)
        end

        File.utime(DEFAULT_TIMESTAMP, DEFAULT_TIMESTAMP, staging_dir)
      end

      def find_executable(cmd)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |path|
          exts.each do |ext|
            exe = File.join(path, cmd + ext)
            return exe if File.exist?(exe) && File.executable?(exe)
          end
        end
        nil
      end

      def windows?
        Gem.win_platform?
      end

      def powershell_escape(value)
        "'#{value.to_s.gsub("'", "''")}'"
      end
    end

    class PackageError < StandardError; end
  end
end

exit AICabinets::Packaging.run
