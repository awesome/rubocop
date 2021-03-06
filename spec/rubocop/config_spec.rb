# encoding: utf-8

require 'spec_helper'

DEFAULT_CONFIG = Rubocop::Config.load_file('config/default.yml')

describe Rubocop::Config do
  include FileHelper

  subject(:configuration) { Rubocop::Config.new(hash, loaded_path) }
  let(:hash) { {} }
  let(:loaded_path) { 'example/.rubocop.yml' }

  describe '.configuration_file_for', :isolated_environment do
    subject(:configuration_file_for) do
      Rubocop::Config.configuration_file_for(dir_path)
    end

    context 'when no config file exists in ancestor directories' do
      let(:dir_path) { 'dir' }
      before { create_file('dir/example.rb', '') }

      context 'but a config file exists in home directory' do
        before { create_file('~/.rubocop.yml', '') }

        it 'returns the path to the file in home directory' do
          expect(configuration_file_for).to end_with('home/.rubocop.yml')
        end
      end

      context 'and no config file exists in home directory' do
        it 'falls back to the provided default file' do
          expect(configuration_file_for).to end_with('config/default.yml')
        end
      end
    end

    context 'when a config file exists in the parent directory' do
      let(:dir_path) { 'dir' }

      before do
        create_file('dir/example.rb', '')
        create_file('.rubocop.yml', '')
      end

      it 'returns the path to that configuration file' do
        expect(configuration_file_for).to end_with('work/.rubocop.yml')
      end
    end

    context 'when multiple config files exist in ancestor directories' do
      let(:dir_path) { 'dir' }

      before do
        create_file('dir/example.rb', '')
        create_file('dir/.rubocop.yml', '')
        create_file('.rubocop.yml', '')
      end

      it 'prefers closer config file' do
        expect(configuration_file_for).to end_with('dir/.rubocop.yml')
      end
    end
  end

  describe '.configuration_from_file', :isolated_environment do
    subject(:configuration_from_file) do
      Rubocop::Config.configuration_from_file(file_path)
    end

    context 'with any config file' do
      let(:file_path) { '.rubocop.yml' }

      before do
        create_file(file_path, ['Encoding:',
                                '  Enabled: false'])
      end
      it 'returns a configuration inheriting from default.yml' do
        config = DEFAULT_CONFIG['Encoding'].dup
        config['Enabled'] = false
        expect(configuration_from_file)
          .to eql(DEFAULT_CONFIG.merge('Encoding' => config))
      end
    end

    context 'when multiple config files exist in ancestor directories' do
      let(:file_path) { 'dir/.rubocop.yml' }

      before do
        create_file('.rubocop.yml',
                    ['AllCops:',
                     '  Excludes:',
                     '    - vendor/**',
                    ])

        create_file(file_path,
                    ['AllCops:',
                     '  Excludes: []',
                    ])
      end

      it 'gets AllCops/Excludes from the highest directory level' do
        excludes = configuration_from_file['AllCops']['Excludes']
        expect(excludes).to eq([File.expand_path('vendor/**')])
      end
    end

    context 'when a file inherits from a parent file' do
      let(:file_path) { 'dir/.rubocop.yml' }

      before do
        create_file('.rubocop.yml',
                    ['AllCops:',
                     '  Excludes:',
                     '    - vendor/**',
                     '    - !ruby/regexp /[A-Z]/',
                    ])

        create_file(file_path, ['inherit_from: ../.rubocop.yml'])
      end

      it 'gets an absolute AllCops/Excludes' do
        excludes = configuration_from_file['AllCops']['Excludes']
        expect(excludes).to eq([File.expand_path('vendor/**'), /[A-Z]/])
      end
    end

    context 'when a file inherits from a sibling file' do
      let(:file_path) { 'dir/.rubocop.yml' }

      before do
        create_file('src/.rubocop.yml',
                    ['AllCops:',
                     '  Excludes:',
                     '    - vendor/**',
                    ])

        create_file(file_path, ['inherit_from: ../src/.rubocop.yml'])
      end

      it 'gets an absolute AllCops/Exclude' do
        excludes = configuration_from_file['AllCops']['Excludes']
        expect(excludes).to eq([File.expand_path('src/vendor/**')])
      end
    end

    context 'when a file inherits from a parent and grandparent file' do
      let(:file_path) { 'dir/subdir/.rubocop.yml' }

      before do
        create_file('dir/subdir/example.rb', '')

        create_file('.rubocop.yml',
                    ['LineLength:',
                     '  Enabled: false',
                     '  Max: 77'])

        create_file('dir/.rubocop.yml',
                    ['inherit_from: ../.rubocop.yml',
                     '',
                     'MethodLength:',
                     '  Enabled: true',
                     '  CountComments: false',
                     '  Max: 10'
                    ])

        create_file(file_path,
                    ['inherit_from: ../.rubocop.yml',
                     '',
                     'LineLength:',
                     '  Enabled: true',
                     '',
                     'MethodLength:',
                     '  Max: 5'
                    ])
      end

      it 'returns the ancestor configuration plus local overrides' do
        config = DEFAULT_CONFIG
                   .merge('LineLength' => {
                          'Description' =>
                             DEFAULT_CONFIG['LineLength']['Description'],
                          'Enabled' => true,
                          'Max' => 77
                          },
                          'MethodLength' => {
                            'Description' =>
                               DEFAULT_CONFIG['MethodLength']['Description'],
                            'Enabled' => true,
                            'CountComments' => false,
                            'Max' => 5
                          })
        expect(configuration_from_file).to eq(config)
      end
    end

    context 'when a file inherits from two configurations' do
      let(:file_path) { '.rubocop.yml' }

      before do
        create_file('example.rb', '')

        create_file('normal.yml',
                    ['MethodLength:',
                     '  Enabled: false',
                     '  CountComments: true',
                     '  Max: 79'])

        create_file('special.yml',
                    ['MethodLength:',
                     '  Enabled: false',
                     '  Max: 200'])

        create_file(file_path,
                    ['inherit_from:',
                     '  - normal.yml',
                     '  - special.yml',
                     '',
                     'MethodLength:',
                     '  Enabled: true'
                    ])
      end

      it 'returns values from the last one when possible' do
        expected = { 'Enabled' => true,        # overridden in .rubocop.yml
                     'CountComments' => true,  # only defined in normal.yml
                     'Max' => 200 }            # special.yml takes precedence
        expect(configuration_from_file['MethodLength'].to_set)
          .to be_superset(expected.to_set)
      end
    end
  end

  describe '.load_file', :isolated_environment do
    subject(:load_file) do
      Rubocop::Config.load_file(configuration_path)
    end

    let(:configuration_path) { '.rubocop.yml' }

    it 'returns a configuration loaded from the passed path' do
      create_file(configuration_path, [
        'Encoding:',
        '  Enabled: true',
      ])
      configuration = load_file
      expect(configuration['Encoding']).to eq({
        'Enabled' => true
      })
    end
  end

  describe '.merge' do
    subject(:merge) { Rubocop::Config.merge(base, derived) }

    let(:base) do
      {
        'AllCops' => {
          'Includes' => ['**/*.gemspec', '**/Rakefile'],
          'Excludes' => []
        }
      }
    end
    let(:derived) do
      { 'AllCops' => { 'Excludes' => ['example.rb', 'exclude_*'] } }
    end

    it 'returns a recursive merge of its two arguments' do
      expect(merge).to eq('AllCops' => {
                            'Includes' => ['**/*.gemspec', '**/Rakefile'],
                            'Excludes' => ['example.rb', 'exclude_*']
                          })
    end
  end

  describe '#validate', :isolated_environment do
    # TODO: Because Config.load_file now outputs the validation warning,
    #       it is inserting text into the rspec test output here.
    #       The next 2 lines should be removed eventually.
    before(:each) { $stdout = StringIO.new }
    after(:each) { $stdout = STDOUT }

    subject(:configuration) do
      Rubocop::Config.load_file(configuration_path)
    end

    let(:configuration_path) { '.rubocop.yml' }

    context 'when the configuration includes any unrecognized cop name' do
      before do
        create_file(configuration_path, [
          'LyneLenth:',
          '  Enabled: true',
          '  Max: 100',
        ])
      end

      it 'raises validation error' do
        expect do
          configuration.validate
        end.to raise_error(Rubocop::Config::ValidationError) do |error|
          expect(error.message).to start_with('unrecognized cop LyneLenth')
        end
      end
    end

    context 'when the configuration includes any unrecognized parameter' do
      before do
        create_file(configuration_path, [
          'LineLength:',
          '  Enabled: true',
          '  Min: 10',
        ])
      end

      it 'raises validation error' do
        expect do
          configuration.validate
        end.to raise_error(Rubocop::Config::ValidationError) do |error|
          expect(error.message).to
            start_with('unrecognized parameter LineLength:Min')
        end
      end
    end
  end

  describe '#file_to_include?' do
    let(:hash) do
      {
        'AllCops' => {
          'Includes' => ['Gemfile', 'config/unicorn.rb.example']
        }
      }
    end

    let(:loaded_path) { '/home/foo/project/.rubocop.yml' }

    context 'when the passed path matches any of patterns to include' do
      it 'returns true' do
        file_path = '/home/foo/project/Gemfile'
        expect(configuration.file_to_include?(file_path)).to be_true
      end
    end

    context 'when the passed path does not match any of patterns to include' do
      it 'returns false' do
        file_path = '/home/foo/project/Gemfile.lock'
        expect(configuration.file_to_include?(file_path)).to be_false
      end
    end
  end

  describe '#file_to_exclude?' do
    let(:hash) do
      {
        'AllCops' => {
          'Excludes' => ['/home/foo/project/log/*']
        }
      }
    end

    let(:loaded_path) { '/home/foo/project/.rubocop.yml' }

    context 'when the passed path matches any of patterns to exclude' do
      it 'returns true' do
        file_path = '/home/foo/project/log/foo.rb'
        expect(configuration.file_to_exclude?(file_path)).to be_true
      end
    end

    context 'when the passed path does not match any of patterns to exclude' do
      it 'returns false' do
        file_path = '/home/foo/project/log_file.rb'
        expect(configuration.file_to_exclude?(file_path)).to be_false
      end
    end
  end

  describe '#patterns_to_include' do
    subject(:patterns_to_include) do
      configuration = Rubocop::Config.new(hash, loaded_path)
      configuration.patterns_to_include
    end

    let(:hash) { {} }
    let(:loaded_path) { 'example/.rubocop.yml' }

    context 'when config file has AllCops => Includes key' do
      let(:hash) do
        {
          'AllCops' => {
            'Includes' => ['Gemfile', 'config/unicorn.rb.example']
          }
        }
      end

      it 'returns the Includes value' do
        expect(patterns_to_include).to eq([
          'Gemfile',
          'config/unicorn.rb.example'
        ])
      end
    end
  end

  describe '#patterns_to_exclude' do
    subject(:patterns_to_exclude) do
      configuration = Rubocop::Config.new(hash, loaded_path)
      configuration.patterns_to_exclude
    end

    let(:hash) { {} }
    let(:loaded_path) { 'example/.rubocop.yml' }

    context 'when config file has AllCops => Excludes key' do
      let(:hash) do
        {
          'AllCops' => {
            'Excludes' => ['log/*']
          }
        }
      end

      it 'returns the Excludes value' do
        expect(patterns_to_exclude).to eq(['log/*'])
      end
    end
  end

  describe 'configuration for SymbolArray', :isolated_environment do
    let(:config) do
      config_path = Rubocop::Config.configuration_file_for('.')
      Rubocop::Config.configuration_from_file(config_path)
    end

    context 'when no config file exists for the target file' do
      it 'is disabled' do
        expect(config.cop_enabled?('SymbolArray')).to be_false
      end
    end

    context 'when a config file which does not mention SymbolArray exists' do
      it 'is disabled' do
        create_file('.rubocop.yml', [
          'LineLength:',
          '  Max: 79'
        ])
        expect(config.cop_enabled?('SymbolArray')).to be_false
      end
    end

    context 'when a config file which explicitly enables SymbolArray exists' do
      it 'is enabled' do
        create_file('.rubocop.yml', [
          'SymbolArray:',
          '  Enabled: true'
        ])
        expect(config.cop_enabled?('SymbolArray')).to be_true
      end
    end
  end

  describe 'configuration for SymbolName' do
    describe 'AllowCamelCase' do
      it 'is enabled by default' do
        default_config = Rubocop::Config.default_configuration
        symbol_name_config = default_config.for_cop('SymbolName')
        expect(symbol_name_config['AllowCamelCase']).to be_true
      end
    end
  end
end
