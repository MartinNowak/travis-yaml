require 'bundler/setup'
require 'travis/yaml'

module Travis::Yaml
  def spec(**options)
    Nodes::Root.spec(**options)
  end

  module Nodes
    TEMPLATE_VARS = Notifications::Template::VARIABLES.map { |v| "`%{#{v}}`"}.join(", ")
    SPEC_DESCRIPTIONS = {
      Stage => "Commands that will be run on the VM.",
      Notifications::Template => "Strings will be interpolated. Available variables: #{TEMPLATE_VARS}."
    }

    TYPES = {
      binary: 'binary string',
      bool:   'boolean value',
      float:  'float value',
      int:    'integer value',
      null:   'null value',
      str:    'string',
      time:   'time value',
      secure: 'encrypted string'
    }

    class Node
      def self.spec_description(*prefix)
        description = SPEC_DESCRIPTIONS[prefix]
        ancestors.each { |a| description ||= SPEC_DESCRIPTIONS[a] }
        description
      end

      def self.spec_format
      end

      def self.spec(*prefix, **options)
        options[:experimental] ||= false
        options[:required]     ||= false
        [{ key: prefix, description: spec_description(prefix), format: spec_format, **options }]
      end
    end

    class Scalar
      def self.spec_format(append = "")
        formats = cast.any? ? cast : [default_type]
        formats.map { |f| TYPES[f] ? TYPES[f]+append : f.to_s }.join(', ').gsub(/,([^,]+)$/, ' or \1')
      end
    end

    class FixedValue
      def self.spec_description(*prefix)
        super || begin
          list = valid_values.map { |v| "`#{v}`#{" (default)" if default == v.to_s}" }.join(', ').gsub(/,([^,]+)$/, ' or \1')
          if aliases.any?
            alias_list = aliases.map { |k,v| "`#{k}` for `#{v}`" }.join(', ').gsub(/,([^,]+)$/, ' or \1')
            list += "; or one of the known aliases: #{alias_list}"
          end
          "Value has to be #{list}. Setting is#{" not" if ignore_case?} case sensitive."
        end
      end
    end

    class Sequence
      def self.spec_format
        "list of " << type.spec_format("s") << "; or a single " << type.spec_format if type.spec_format
      end

      def self.spec(*prefix, **options)
        specs = super
        specs += type.spec(*prefix, '[]') unless type <= Scalar
        specs
      end
    end

    class Root
      def self.spec(*)
        super[1..-1].sort_by { |e| e[:key] }
      end
    end

    class OpenMapping
      # def self.spec(*prefix, **options)
      #   super + default_type.spec(*prefix, '*')
      # end
    end

    class Mapping
      def self.spec_format(append = "")
        "key value mapping#{append}"
      end

      def self.default_spec_description
        "a key value map"
      end

      def self.spec_options(key, **options)
        { required: required.include?(key), experimental: experimental.include?(key) }
      end

      def self.spec_aliases(*prefix, **options)
        aliases.map { |k,v| { key: [*prefix, k], alias_for: [*prefix, v], **spec_options(k, **options) } }
      end

      def self.spec(*prefix, **options)
        specs = mapping.sort_by(&:first).inject(super) { |l, (k,v)| l + v.spec(*prefix, k, **spec_options(k, **options)) }
        specs + spec_aliases(*prefix, **options)
      end
    end
  end
end

content = <<-MARKDOWN
## The `.travis.yml` Format
Here is a list of all the options understood by travis-yaml.

Note that stricitly speaking Travis CI might not have the same understanding of these as travis-yaml has at the moment, since travis-yaml is not yet being used.

### Available Options
MARKDOWN

Travis::Yaml.spec.each do |entry|
  content << "#### `" << entry[:key].join('.').gsub('.[]', '[]') << "`\n"
  content << "**This setting is required!**\n\n" if entry[:required]
  content << "**This setting is experimental and might be removed!**\n\n" if entry[:experimental]
  if entry[:alias_for] and other = entry[:alias_for].join('.')
    content << "Alias for " << "[`#{other}`](##{other})." << "\n"
  else
    content << entry[:description] << "\n\n" if entry[:description]
    content << "**Expected format:** " <<  entry[:format].capitalize << ".\n\n" if entry[:format]
  end
end

content << <<-MARKDOWN
## Generating the Specification

This file is generated. You currently update it by running `play/spec.rb`.
MARKDOWN

File.write('SPEC.md', content)