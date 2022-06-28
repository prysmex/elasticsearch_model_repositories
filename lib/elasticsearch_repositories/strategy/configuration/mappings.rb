module ElasticsearchRepositories
  module Strategy
    module Configuration

      # Utility class for elasticsearch index mappings
      #
      class Mappings
        attr_accessor :options, :strategy, :mapping, :runtime_fields, :dynamic_properties_methods

        # @private
        TYPES_WITH_EMBEDDED_PROPERTIES = %w(object nested)

        # @param [Hash] options index mappings options (dynamic, etc...)
        # @param [ElasticsearchRepositories::BaseStrategy] strategy
        def initialize(options={}, strategy=nil)
          self.instance_variable_set('@dynamic_properties_methods', [])
          @options = options
          @strategy = strategy
          @mapping = {}
          @runtime_fields = {}
        end

        #
        # Used to define new fields in the mappings. Use blocks to define nested fields
        #
        # @param [Symbol] field_name
        # @param [Hash] definition field definition
        #
        # @return [Mappings] self
        def indexes(field_name, definition={}, &block)
          @mapping[field_name] = definition

          if block_given?
            @mapping[field_name][:type] ||= 'object'
            properties = TYPES_WITH_EMBEDDED_PROPERTIES.include?(@mapping[field_name][:type].to_s) ? :properties : :fields

            @mapping[field_name][properties] ||= {}

            previous = @mapping
            begin
              @mapping = @mapping[field_name][properties]
              self.instance_eval(&block)
            ensure
              @mapping = previous
            end
          end

          # Set the type to `text` by default
          @mapping[field_name][:type] ||= 'text'

          self
        end

        # Defines a new runtime filed
        #
        # @param [String] field_name
        # @param [Hash] definition
        #
        # @return [void]
        def runtime_field(field_name, definition)
          @runtime_fields[field_name] = definition
        end

        # Registers a new method to be executed when serializing in #to_hash
        # The arguments should be passed as a hash where the key is the method's name
        # when calling #to_hash
        #
        # @param [Symbol] method_name
        # @param [Proc] &block
        # @return [void]
        def register_dynamic_properties_method(method_name, &block)
          define_singleton_method(method_name, &block) if block_given?

          methods = self.instance_variable_get('@dynamic_properties_methods')
          methods.push(method_name).uniq
          self.instance_variable_set('@dynamic_properties_methods', methods)
        end

        # Serialize into hash. If any methods where registed using #register_dynamic_properties_method,
        # arguments should be passed or use _dynamic_properties_methods_to_skip param
        # 
        # @param [Array] _dynamic_properties_methods_to_skip
        # @param [Hash] dynamic_properties_methods_args where key is method name and value are the arguments
        # @return [Hash] serialized mappings
        def to_hash(_dynamic_properties_methods_to_skip: [], **dynamic_properties_methods_args)

          # static properties
          mappings_hash = @options.merge(properties: @mapping, runtime: @runtime_fields)

          #prevent pollution of @mapping since it is cached
          mappings_hash = Marshal.load(Marshal.dump(mappings_hash))

          # support dynamic properties
          dynamic_properties_methods.each do |method_name|
            next if _dynamic_properties_methods_to_skip.include?(method_name)
            self.public_send(method_name, mappings_hash, *dynamic_properties_methods_args[method_name])
          end

          mappings_hash
        end

        # @example
        #   {
        #     "id" => "integer",
        #     "created_by"=>"object",
        #     "created_by.id"=>"integer",
        #     "created_by.full_name.raw"=>"keyword",
        #   }
        #
        # @return [Hash] flattened mappings
        def to_flattened_hash
          datatypes = [
            'binary', 'boolean', 'date', 'date_nanos', 'dense_vector', 'flattened',
            'geo_point', 'geo_shape', 'histogram', 'ip', 'join', 'keyword', 'nested',
            'long', 'integer', 'short' 'byte', 'double', 'float', 'half_float', 'scaled_float', 'unsigned_long', # numeric datatypes
            'object', 'percolator' 'point', 'range', 'rank_feature', 'rank_features', 'search_as_you_type',
            'shape', 'sparce_vector', 'text', 'token_count' 'version'
          ]

          mappings_hash = self.to_hash
          flattened = SuperHash::Utils.flatten_to_root(mappings_hash[:properties])
    
          # remove key value pairs that are not a datatype, like mapping options
          flattened = flattened.select{|k,v| datatypes.include?(v) }
    
          flattened.transform_keys do |k|
            # remove '.type' keyword from all keys
            new_k = k.to_s.gsub(/\.type/, '')
    
            # remove object keywords
            new_k.gsub(/\.?properties|\.type|\.?fields/, '')
          end
        end

      end

    end
  end
end