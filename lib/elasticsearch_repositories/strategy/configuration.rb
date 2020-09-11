module ElasticsearchRepositories
  module Strategy
    module Configuration

      # Wraps the [index settings](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
      #
      class Settings
        attr_accessor :settings

        def initialize(settings={})
          @settings = settings
        end

        def to_hash
          @settings
        end

        def as_json(options={})
          to_hash
        end
      end

      # Wraps the [index mappings](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html)
      #
      class Mappings
        attr_accessor :options, :type

        # @private
        TYPES_WITH_EMBEDDED_PROPERTIES = %w(object nested)

        def initialize(type = nil, options={})
          @type    = type
          @options = options
          @mapping = {}
        end

        def indexes(name, options={}, &block)
          @mapping[name] = options

          if block_given?
            @mapping[name][:type] ||= 'object'
            properties = TYPES_WITH_EMBEDDED_PROPERTIES.include?(@mapping[name][:type].to_s) ? :properties : :fields

            @mapping[name][properties] ||= {}

            previous = @mapping
            begin
              @mapping = @mapping[name][properties]
              self.instance_eval(&block)
            ensure
              @mapping = previous
            end
          end

          # Set the type to `text` by default
          @mapping[name][:type] ||= 'text'

          self
        end

        def to_hash
          if @type
            { @type.to_sym => @options.merge( properties: @mapping ) }
          else
            @options.merge( properties: @mapping )
          end
        end

        def as_json(options={})
          to_hash
        end
      end

      module Methods
        #index name for searching records
        def search_index_name
        end
  
        #get the target index for a specific record
        def target_index_name(record)
        end
  
        #Used by index management module
        def current_index
        end
  
        #index mappings
        def mappings(options={}, &block)
          @cached_mapping ||= Mappings.new()
  
          @cached_mapping.options.update(options) unless options.empty?
          if block_given?
            @cached_mapping.instance_eval(&block)
          else
            @cached_mapping
          end
        end
  
        # This creates a hash that may be merged in runtime.
        def dynamic_mappings_hash
          mappings.to_hash
        end
  
        #index settings
        def settings(options={}, &block)
          @cached_setting ||= Settings.new()
  
          @cached_setting.options.update(options) unless options.empty?
          if block_given?
            @cached_setting.instance_eval(&block)
          else
            @cached_setting
          end
        end
      end
      
    end
  end
end