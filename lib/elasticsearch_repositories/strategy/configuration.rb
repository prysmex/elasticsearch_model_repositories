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

        def as_json
          to_hash
        end
      end

      # Wraps the [index mappings](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html)
      #
      class Mappings
        attr_accessor :type, :options, :strategy, :dynamic_fields_methods

        # @private
        TYPES_WITH_EMBEDDED_PROPERTIES = %w(object nested)

        def initialize(type = nil, options={}, strategy=nil)
          @type    = type
          @options = options
          @strategy = strategy
          self.instance_variable_set('@dynamic_fields_methods', [])
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

        def register_dynamic_fields_method(method_name)
           methods = self.instance_variable_get('@dynamic_fields_methods')
           methods.push(method_name)
           self.instance_variable_set('@dynamic_fields_methods', methods)
        end

        def to_hash(dynamic_fields_args={})
          base_hash = if @type
            { @type.to_sym => @options.merge( properties: @mapping ) }
          else
            @options.merge( properties: @mapping )
          end
          #merge dynamic mappings from registered dynamic_fields_methods
          dynamic_hash = dynamic_fields_methods.reduce({}) do |h, name|
            if @strategy.host.method(name).arity != 0
              h.merge(@strategy.host.public_send(name, *dynamic_fields_args[name]))
            else
              h.merge(@strategy.host.public_send(name))
            end
          end
          base_hash[:properties] = base_hash[:properties].merge(dynamic_hash)
          base_hash
        end

        def as_json
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
        def current_index_name
        end

        def mappings
          @cached_mapping
        end
  
        #index mappings
        def set_mappings(options={}, &block)
          @cached_mapping ||= Mappings.new(nil, options, self)
  
          @cached_mapping.options.update(options) unless options.empty?
          if block_given?
            @cached_mapping.instance_eval(&block)
          else
            @cached_mapping
          end
        end

        def settings
          @cached_settings
        end
  
        #index settings
        def set_settings(settings={}, &block)
          # settings = YAML.load(settings.read) if settings.respond_to?(:read)
          @cached_settings ||= Settings.new(settings)

          @cached_settings.settings.update(settings) unless settings.empty?

          if block_given?
            self.instance_eval(&block)
            return self
          else
            @cached_settings
          end
        end

      end
      
    end
  end
end